import Darwin
import Foundation

public actor LaunchctlServiceRepository: LaunchdRepository {
    static let defaultUnloadVerificationAttempts = 31
    static let defaultUnloadVerificationDelay: Duration = .seconds(1)

    private struct LoadedState {
        let isLoaded: Bool
        let pid: Int32?
        let lastExitStatus: Int32?
    }

    private let kind: ServiceKind
    private let paths: MoyPaths
    private let fileManager: FileManager
    private let processRunner: any ProcessRunning
    private let plistWriter: LaunchdPlistWriter
    private let userID: uid_t
    private let unloadVerificationAttempts: Int
    private let unloadVerificationDelay: Duration

    public init(
        paths: MoyPaths = .defaults(),
        kind: ServiceKind = .launchAgent,
        fileManager: FileManager = .default,
        processRunner: any ProcessRunning = DefaultProcessRunner(),
        plistWriter: LaunchdPlistWriter = .init(),
        userID: uid_t = getuid(),
    ) {
        self.kind = kind
        self.paths = paths
        self.fileManager = fileManager
        self.processRunner = processRunner
        self.plistWriter = plistWriter
        self.userID = userID
        unloadVerificationAttempts = Self.defaultUnloadVerificationAttempts
        unloadVerificationDelay = Self.defaultUnloadVerificationDelay
    }

    init(
        paths: MoyPaths,
        fileManager: FileManager,
        processRunner: any ProcessRunning,
        plistWriter: LaunchdPlistWriter,
        userID: uid_t,
        unloadVerificationAttempts: Int,
        unloadVerificationDelay: Duration,
    ) {
        kind = .launchAgent
        self.paths = paths
        self.fileManager = fileManager
        self.processRunner = processRunner
        self.plistWriter = plistWriter
        self.userID = userID
        self.unloadVerificationAttempts = max(1, unloadVerificationAttempts)
        self.unloadVerificationDelay = unloadVerificationDelay
    }

    public func status(identifier: ServiceIdentifier) async throws -> ServiceStatus {
        let hasPlist = fileManager.fileExists(atPath: paths.plistFile(identifier: identifier, kind: kind).path)
        let loaded = try await loadedState(identifier: identifier)
        let registration: ServiceStatus.Registration = switch (hasPlist, loaded.isLoaded) {
        case (false, false): .disabled
        case (true, true): .enabled
        case (true, false): .plistOnly
        case (false, true): .loadedOnly
        }
        let runtime: ServiceStatus.Runtime = if let pid = loaded.pid {
            .running(pid: pid)
        } else if loaded.isLoaded {
            .waiting
        } else {
            .notLoaded
        }
        return ServiceStatus(
            identifier: identifier,
            registration: registration,
            runtime: runtime,
            lastExitStatus: loaded.lastExitStatus,
        )
    }

    public func enable(_ service: ServiceDefinition) async throws {
        guard service.kind == kind else { throw MoyError.kindCannotChange }
        try requirePrivilege()
        let identifier = service.identifier
        let current = try await status(identifier: identifier)
        switch current.registration {
        case .disabled:
            break
        case .enabled:
            throw MoyError.alreadyEnabled(identifier.rawValue)
        case .plistOnly, .loadedOnly:
            throw MoyError.inconsistentState(identifier.rawValue)
        }

        try prepareOutputDirectories(for: service)
        let plistURL = paths.plistFile(identifier: identifier, kind: kind)
        try plistWriter.write(service, to: plistURL)
        if kind == .launchDaemon {
            try fileManager.setAttributes([.ownerAccountID: 0, .groupOwnerAccountID: 0], ofItemAtPath: plistURL.path)
        }
        let arguments = ["bootstrap", domainTarget, plistURL.path]
        do {
            let result = try await processRunner.run(executable: "/bin/launchctl", arguments: arguments)
            guard result.status == 0 else {
                throw launchctlError(arguments: arguments, result: result)
            }
            guard try await status(identifier: identifier).registration == .enabled else {
                throw MoyError.inconsistentState(identifier.rawValue)
            }
        } catch {
            // A concurrent enable may own the loaded registration. Preserve it,
            // including its plist, unless launchd confirms the service is absent.
            if let loaded = try? await loadedState(identifier: identifier), !loaded.isLoaded {
                try? fileManager.removeItem(at: plistURL)
            }
            throw error
        }
    }

    public func disable(identifier: ServiceIdentifier) async throws {
        try requirePrivilege()
        let current = try await status(identifier: identifier)
        switch current.registration {
        case .disabled:
            throw MoyError.notEnabled(identifier.rawValue)
        case .enabled, .loadedOnly:
            let arguments = ["bootout", serviceTarget(identifier: identifier)]
            let result = try await processRunner.run(executable: "/bin/launchctl", arguments: arguments)
            guard result.status == 0 else {
                throw launchctlError(arguments: arguments, result: result)
            }
            guard try await waitUntilUnloaded(identifier: identifier) else {
                throw MoyError.inconsistentState(identifier.rawValue)
            }
        case .plistOnly:
            break
        }

        let plistURL = paths.plistFile(identifier: identifier, kind: kind)
        guard fileManager.fileExists(atPath: plistURL.path) else { return }
        do {
            try fileManager.removeItem(at: plistURL)
        } catch {
            throw MoyError.fileOperation(path: plistURL.path, reason: error.localizedDescription)
        }
    }

    public func restart(identifier: ServiceIdentifier) async throws {
        try requirePrivilege()
        guard try await loadedState(identifier: identifier).isLoaded else {
            throw MoyError.notEnabled(identifier.rawValue)
        }
        let arguments = ["kickstart", "-k", serviceTarget(identifier: identifier)]
        let result = try await processRunner.run(executable: "/bin/launchctl", arguments: arguments)
        guard result.status == 0 else {
            throw launchctlError(arguments: arguments, result: result)
        }
    }
}

private extension LaunchctlServiceRepository {
    func requirePrivilege() throws {
        if kind == .launchDaemon, geteuid() != 0 {
            throw MoyError.administratorRequired
        }
    }

    var domainTarget: String {
        kind == .launchDaemon ? "system" : "gui/\(userID)"
    }

    func serviceTarget(identifier: ServiceIdentifier) -> String {
        "\(domainTarget)/\(identifier.launchdLabel)"
    }

    private func loadedState(identifier: ServiceIdentifier) async throws -> LoadedState {
        let arguments = ["print", serviceTarget(identifier: identifier)]
        let result = try await processRunner.run(executable: "/bin/launchctl", arguments: arguments)
        if result.status != 0 {
            if LaunchctlOutputParser.isMissingService(result.output) {
                return LoadedState(isLoaded: false, pid: nil, lastExitStatus: nil)
            }
            throw launchctlError(arguments: arguments, result: result)
        }
        let state = LaunchctlOutputParser().parse(result.output)
        return LoadedState(isLoaded: true, pid: state.pid, lastExitStatus: state.lastExitStatus)
    }

    func waitUntilUnloaded(identifier: ServiceIdentifier) async throws -> Bool {
        for attempt in 0 ..< unloadVerificationAttempts {
            guard try await loadedState(identifier: identifier).isLoaded else { return true }
            if attempt + 1 < unloadVerificationAttempts {
                try await Task.sleep(for: unloadVerificationDelay)
            }
        }
        return false
    }

    func prepareOutputDirectories(for service: ServiceDefinition) throws {
        let directories = [service.standardOutPath, service.standardErrorPath]
            .map { URL(filePath: $0).deletingLastPathComponent() }
        do {
            for directory in Set(directories) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        } catch {
            throw MoyError.fileOperation(path: paths.logDirectory.path, reason: error.localizedDescription)
        }
    }

    func launchctlError(arguments: [String], result: ProcessResult) -> MoyError {
        MoyError.launchctlFailed(
            arguments: arguments,
            status: result.status,
            message: result.output.isEmpty ? "No error message" : result.output,
        )
    }
}
