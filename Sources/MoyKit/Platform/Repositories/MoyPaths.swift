import Foundation

public struct MoyPaths: Equatable, Sendable {
    public let dataDirectory: URL
    public let launchAgentsDirectory: URL
    public let logDirectory: URL

    public init(dataDirectory: URL, launchAgentsDirectory: URL, logDirectory: URL) {
        self.dataDirectory = dataDirectory
        self.launchAgentsDirectory = launchAgentsDirectory
        self.logDirectory = logDirectory
    }

    public static func defaults(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> Self {
        let home = fileManager.homeDirectoryForCurrentUser
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

    public func plistFile(identifier: ServiceIdentifier) -> URL {
        launchAgentsDirectory.appending(path: "\(identifier.launchdLabel).plist")
    }

    public func standardOutFile(identifier: ServiceIdentifier) -> URL {
        logFile(label: identifier.launchdLabel, suffix: "stdout")
    }

    public func standardErrorFile(identifier: ServiceIdentifier) -> URL {
        logFile(label: identifier.launchdLabel, suffix: "stderr")
    }

    public func standardOutFilePreview(identifier: ServiceIdentifier?) -> URL {
        logFile(
            label: identifier?.launchdLabel ?? "\(ServiceIdentifier.launchdLabelPrefix)<Identifier>",
            suffix: "stdout",
        )
    }

    public func standardErrorFilePreview(identifier: ServiceIdentifier?) -> URL {
        logFile(
            label: identifier?.launchdLabel ?? "\(ServiceIdentifier.launchdLabelPrefix)<Identifier>",
            suffix: "stderr",
        )
    }

    private func logFile(label: String, suffix: String) -> URL {
        logDirectory.appending(path: "\(label).\(suffix).log")
    }
}
