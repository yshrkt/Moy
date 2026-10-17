enum CLIAction: Sendable {
    case refreshStatus
    case receiveStatus(Result<CLIInstallationStatus, SettingsFailure>)
    case install
    case receiveInstallation(Result<Void, SettingsFailure>)
    case cancelInstallation
    case requestUninstallation
    case dismissUninstallation
    case uninstall
    case receiveUninstallation(Result<Void, SettingsFailure>)
    case cancelUninstallation
    case reveal
    case receiveReveal(Result<Void, SettingsFailure>)
}
