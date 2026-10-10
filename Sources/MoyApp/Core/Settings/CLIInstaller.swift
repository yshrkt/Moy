import Foundation

actor CLIInstaller {
    static let installationPath = "/usr/local/bin/moy"

    private let sourceURL: URL
    private let destinationURL: URL
    private let authorizationClient: CLIInstallerAuthorizationClient

    init(
        sourceURL: URL = Bundle.main.bundleURL.appending(path: "Contents/Helpers/moy"),
        destinationURL: URL = URL(fileURLWithPath: CLIInstaller.installationPath),
        authorizationClient: CLIInstallerAuthorizationClient = .live,
    ) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.authorizationClient = authorizationClient
    }

    func status() throws -> CLIInstallationStatus {
        let fileManager = FileManager.default
        let attributes: [FileAttributeKey: Any]
        do {
            // Unlike fileExists, this also finds dangling symbolic links.
            attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        } catch CocoaError.fileReadNoSuchFile {
            return .notInstalled
        }
        guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else {
            return .conflict
        }
        let target = try fileManager.destinationOfSymbolicLink(atPath: destinationURL.path)
        let targetURL = URL(fileURLWithPath: target, relativeTo: destinationURL.deletingLastPathComponent())
        guard targetURL.standardizedFileURL == sourceURL.standardizedFileURL,
              fileManager.isExecutableFile(atPath: sourceURL.path)
        else {
            return .conflict
        }
        return .installed
    }

    func install() async throws {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: sourceURL.path) else {
            throw SettingsFailure.cliNotBundled
        }
        switch try status() {
        case .installed:
            return
        case .conflict:
            throw SettingsFailure.cliDestinationExists
        case .notInstalled:
            break
        }
        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try fileManager.createSymbolicLink(at: destinationURL, withDestinationURL: sourceURL)
        } catch {
            guard Self.isPermissionError(error) else { throw error }
            try await authorizationClient.install(sourceURL, destinationURL)
        }
        guard try status() == .installed else {
            throw SettingsFailure.cliInstallationFailed
        }
    }

    func uninstall() async throws {
        guard try status() == .installed else { throw SettingsFailure.cliLinkChanged }
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: destinationURL.path)
        let targetURL = URL(fileURLWithPath: target, relativeTo: destinationURL.deletingLastPathComponent())
        guard targetURL.standardizedFileURL == sourceURL.standardizedFileURL else {
            throw SettingsFailure.cliLinkChanged
        }
        do {
            guard try status() == .installed else { throw SettingsFailure.cliLinkChanged }
            try FileManager.default.removeItem(at: destinationURL)
        } catch {
            guard Self.isPermissionError(error) else { throw error }
            try await authorizationClient.uninstall(sourceURL, destinationURL, target)
        }
        guard try status() == .notInstalled else { throw SettingsFailure.cliUninstallationFailed }
    }

    private static func isPermissionError(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == CocoaError.fileWriteNoPermission.rawValue {
            return true
        }
        if error.domain == NSPOSIXErrorDomain, [EACCES, EPERM].contains(Int32(error.code)) {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isPermissionError(underlying)
        }
        return false
    }
}
