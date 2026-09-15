enum SettingsAction: Sendable {
    case appear
    case selectTab(SettingsTab)
    case refreshCLIStatus
    case receiveCLIStatus(Result<CLIInstallationStatus, SettingsFailure>)
    case installCLI
    case receiveCLIInstallation(Result<Void, SettingsFailure>)
    case cancelCLIInstallation
    case dismissFailure
}
