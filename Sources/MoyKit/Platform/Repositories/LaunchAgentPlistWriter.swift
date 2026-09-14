import Foundation

public struct LaunchAgentPlistWriter {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func data(for service: ServiceDefinition) throws -> Data {
        try ServiceValidator.validate(service)
        var propertyList: [String: Any] = [
            "Label": service.identifier.launchdLabel,
            "ProgramArguments": service.programArguments,
            "RunAtLoad": service.runAtLoad,
            "KeepAlive": service.keepAlive,
            "StandardOutPath": service.standardOutPath,
            "StandardErrorPath": service.standardErrorPath,
        ]
        if let workingDirectory = service.workingDirectory, !workingDirectory.isEmpty {
            propertyList["WorkingDirectory"] = workingDirectory
        }
        if !service.environmentVariables.isEmpty {
            propertyList["EnvironmentVariables"] = service.environmentVariables
        }
        if let throttleInterval = service.throttleInterval {
            propertyList["ThrottleInterval"] = throttleInterval
        }
        do {
            return try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
        } catch {
            throw MoyError.fileOperation(path: service.identifier.launchdLabel, reason: error.localizedDescription)
        }
    }

    public func write(_ service: ServiceDefinition, to url: URL) throws {
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data(for: service).write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        } catch let error as MoyError {
            throw error
        } catch {
            throw MoyError.fileOperation(path: url.path, reason: error.localizedDescription)
        }
    }
}
