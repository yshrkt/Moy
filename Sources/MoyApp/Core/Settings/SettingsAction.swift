enum SettingsAction: Sendable {
    case appear
    case selectTab(SettingsTab)
    case refreshCLIStatus
    case receiveCLIStatus(Result<CLIInstallationStatus, SettingsFailure>)
    case installCLI
    case receiveCLIInstallation(Result<Void, SettingsFailure>)
    case cancelCLIInstallation
    case requestCLIUninstallation
    case dismissCLIUninstallation
    case uninstallCLI
    case receiveCLIUninstallation(Result<Void, SettingsFailure>)
    case cancelCLIUninstallation
    case revealCLI
    case receiveCLIReveal(Result<Void, SettingsFailure>)
    case dismissFailure
}
