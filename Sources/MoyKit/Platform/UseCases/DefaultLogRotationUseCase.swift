import Darwin
import Foundation

public actor DefaultLogRotationUseCase: LogRotationUseCase {
    // The extra dot makes this label impossible to generate from a user service Identifier.
    public static let label = "com.sputnik-apps.moy.internal.log-rotation"
    private let repository: LocalLogRotationRepository
    private let runner: any ProcessRunning
    private let executable: String

    public init(
        executable: String, paths: MoyPaths = .defaults(),
        runner: any ProcessRunning = DefaultProcessRunner(),
    ) {
        self.executable = executable
        repository = LocalLogRotationRepository(paths: paths)
        self.runner = runner
    }

    public func refresh() async throws -> LogRotationStatus {
        let settings = try repository.settings()
        try await apply(settings)
        return try LogRotationStatus(settings: settings, failures: repository.failures())
    }

    public func update(_ settings: LogRotationSettings) async throws -> LogRotationStatus {
        try repository.save(settings)
        try await apply(settings)
        return try LogRotationStatus(settings: settings, failures: repository.failures())
    }

    private func apply(_ settings: LogRotationSettings) async throws {
        do { try await reconcile(settings) } catch {
            try await recover(settings, failure: error)
        }
    }

    private func recover(_ settings: LogRotationSettings, failure: any Error) async throws -> Never {
        var actual = settings
        do {
            actual.isEnabled = try await isLoaded()
        } catch {
            // Do not invent an OFF state when launchd cannot be queried.
            throw LogRotationError.jobStateUnavailable(
                "\(failure.localizedDescription)\n\(error.localizedDescription)",
            )
        }
        var message = failure.localizedDescription
        do {
            // Persist the observed state so reopening Settings does not silently retry the failed request.
            try repository.save(actual)
        } catch {
            message += "\n\(error.localizedDescription)"
        }
        throw LogRotationError.jobUpdateFailed(actual, message)
    }

    private var jobURL: URL {
        repository.paths.launchAgentsDirectory.appending(path: "\(Self.label).plist")
    }

    private var target: String {
        "gui/\(getuid())/\(Self.label)"
    }

    private func reconcile(_ settings: LogRotationSettings) async throws {
        let manager = FileManager.default
        let existing = try existingJob()
        let exists = existing != nil
        guard settings.isEnabled || exists else { return }
        let loaded = try await isLoaded()
        guard exists || !loaded else { throw LogRotationError.jobConflict(target) }
        let desired = try Self.plist(executable: executable, paths: repository.paths)
        if settings.isEnabled, existing == desired, loaded {
            return
        }
        if loaded {
            try await unload()
        }
        if settings.isEnabled {
            guard manager.isExecutableFile(atPath: executable) else { throw MoyError.executableNotRunnable(executable) }
            try manager.createDirectory(at: jobURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try desired.write(to: jobURL, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: jobURL.path)
            try await launchctl(["bootstrap", "gui/\(getuid())", jobURL.path])
            guard try await isLoaded() else { throw MoyError.inconsistentState(Self.label) }
        } else if exists {
            try manager.removeItem(at: jobURL)
        }
    }

    private func unload() async throws {
        try await launchctl(["bootout", target])
        for _ in 0 ..< 30 {
            if try await !isLoaded() {
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw MoyError.inconsistentState(Self.label)
    }

    private func existingJob() throws -> Data? {
        var attributes = stat()
        guard lstat(jobURL.path, &attributes) == 0 else {
            if errno == ENOENT {
                return nil
            }
            throw MoyError.fileOperation(path: jobURL.path, reason: String(cString: strerror(errno)))
        }
        guard attributes.st_mode & S_IFMT == S_IFREG, attributes.st_uid == getuid()
        else {
            throw LogRotationError.jobConflict(jobURL.path)
        }
        let data = try Data(contentsOf: jobURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["Label"] as? String == Self.label,
              let arguments = plist["ProgramArguments"] as? [String], arguments.count == 2,
              arguments[0].hasSuffix("/Contents/Helpers/moy"), arguments[1] == "internal-rotate-logs"
        else {
            throw LogRotationError.jobConflict(jobURL.path)
        }
        return data
    }

    public static func plist(executable: String, paths: MoyPaths) throws -> Data {
        // Explicit paths preserve the user's configured directories in a launchd environment.
        try PropertyListSerialization.data(fromPropertyList: [
            "Label": label,
            "ProgramArguments": [executable, "internal-rotate-logs"],
            "StartInterval": 3600,
            "RunAtLoad": true,
            "EnvironmentVariables": [
                "MOY_DATA_DIRECTORY": paths.dataDirectory.path,
                "MOY_LOG_DIRECTORY": paths.logDirectory.path,
            ],
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": "/dev/null",
        ], format: .xml, options: 0)
    }

    private func isLoaded() async throws -> Bool {
        let result = try await runner.run(executable: "/bin/launchctl", arguments: ["print", target])
        if result.status == 0 {
            return true
        }
        if result.status == 113 {
            return false
        }
        throw MoyError.launchctlFailed(arguments: ["print", target], status: result.status, message: result.output)
    }

    private func launchctl(_ arguments: [String]) async throws {
        let result = try await runner.run(executable: "/bin/launchctl", arguments: arguments)
        guard result.status == 0 else {
            throw MoyError.launchctlFailed(arguments: arguments, status: result.status, message: result.output)
        }
    }
}
