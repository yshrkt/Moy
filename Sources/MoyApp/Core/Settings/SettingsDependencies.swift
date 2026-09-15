struct SettingsDependencies: Sendable {
    var cliInstallerClient: CLIInstallerClient = .live
}

struct CLIInstallerClient: Sendable {
    var status: @Sendable () async throws -> CLIInstallationStatus
    var install: @Sendable () async throws -> Void

    static let live: Self = {
        let installer = CLIInstaller()
        return Self(
            status: { try await installer.status() },
            install: { try await installer.install() },
        )
    }()
}
