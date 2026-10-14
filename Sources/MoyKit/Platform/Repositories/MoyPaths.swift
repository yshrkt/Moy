import Foundation

public struct MoyPaths: Equatable, Sendable {
    public let dataDirectory: URL
    public let launchAgentsDirectory: URL
    public let launchDaemonsDirectory: URL
    public let daemonLogDirectory: URL
    public let logDirectory: URL

    public init(
        dataDirectory: URL, launchAgentsDirectory: URL, logDirectory: URL,
        launchDaemonsDirectory: URL = URL(filePath: "/Library/LaunchDaemons"),
        daemonLogDirectory: URL = URL(filePath: "/Library/Logs/Moy"),
    ) {
        self.launchDaemonsDirectory = launchDaemonsDirectory
        self.daemonLogDirectory = daemonLogDirectory
        self.dataDirectory = dataDirectory
        self.launchAgentsDirectory = launchAgentsDirectory
        self.logDirectory = logDirectory
    }

    public static func defaults(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil,
    ) -> Self {
        let home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        let dataDirectory = environment["MOY_DATA_DIRECTORY"].map { URL(filePath: $0) }
            ?? home.appending(path: "Library/Application Support/Moy", directoryHint: .isDirectory)
        let launchAgentsDirectory = environment["MOY_LAUNCH_AGENTS_DIRECTORY"].map { URL(filePath: $0) }
            ?? home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
        let logDirectory = environment["MOY_LOG_DIRECTORY"].map { URL(filePath: $0) }
            ?? home.appending(path: "Library/Logs/Moy", directoryHint: .isDirectory)
        return Self(
            dataDirectory: dataDirectory,
            launchAgentsDirectory: launchAgentsDirectory,
            logDirectory: logDirectory,
        )
    }

    public var servicesFile: URL {
        dataDirectory.appending(path: "services.json")
    }

    public var lockFile: URL {
        dataDirectory.appending(path: "services.lock")
    }

    public func plistFile(identifier: ServiceIdentifier, kind: ServiceKind = .launchAgent) -> URL {
        let directory = kind == .launchDaemon ? launchDaemonsDirectory : launchAgentsDirectory
        return directory.appending(path: "\(identifier.launchdLabel).plist")
    }

    public func standardOutFile(identifier: ServiceIdentifier, kind: ServiceKind = .launchAgent) -> URL {
        logFile(label: identifier.launchdLabel, suffix: "stdout", kind: kind)
    }

    public func standardErrorFile(identifier: ServiceIdentifier, kind: ServiceKind = .launchAgent) -> URL {
        logFile(label: identifier.launchdLabel, suffix: "stderr", kind: kind)
    }

    public func standardOutFilePreview(identifier: ServiceIdentifier?, kind: ServiceKind = .launchAgent) -> URL {
        logFile(
            label: identifier?.launchdLabel ?? "\(ServiceIdentifier.launchdLabelPrefix)<Identifier>",
            suffix: "stdout", kind: kind,
        )
    }

    public func standardErrorFilePreview(identifier: ServiceIdentifier?, kind: ServiceKind = .launchAgent) -> URL {
        logFile(
            label: identifier?.launchdLabel ?? "\(ServiceIdentifier.launchdLabelPrefix)<Identifier>",
            suffix: "stderr", kind: kind,
        )
    }

    private func logFile(label: String, suffix: String, kind: ServiceKind) -> URL {
        (kind == .launchDaemon ? daemonLogDirectory : logDirectory).appending(path: "\(label).\(suffix).log")
    }
}
