import Foundation
import MoyKit

struct SettingsDependencies: Sendable {
    var logRotationUseCase: any LogRotationUseCase = DefaultLogRotationUseCase(
        executable: Bundle.main.bundleURL.appending(path: "Contents/Helpers/moy").path,
    )
    var launchAtLoginUseCase: any LaunchAtLoginUseCase = DefaultLaunchAtLoginUseCase()
    var cliInstallerClient: CLIInstallerClient = .live
    var workspaceClient: WorkspaceClient = .live
}

struct CLIInstallerClient: Sendable {
    var status: @Sendable () async throws -> CLIInstallationStatus
    var install: @Sendable () async throws -> Void
    var uninstall: @Sendable () async throws -> Void

    static let live: Self = {
        let installer = CLIInstaller()
        return Self(
            status: { try await installer.status() },
            install: { try await installer.install() },
            uninstall: { try await installer.uninstall() },
        )
    }()
}
