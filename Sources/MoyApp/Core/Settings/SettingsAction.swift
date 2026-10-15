import MoyKit

enum SettingsAction: Sendable {
    case logRotation(LogRotationAction)
    case refreshLaunchAtLoginStatus
    case receiveLaunchAtLoginStatus(LaunchAtLoginStatus)
    case setLaunchAtLogin(Bool)
    case receiveLaunchAtLoginUpdate(LaunchAtLoginStatus, SettingsFailure?)
    case openLoginItemsSettings
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

enum LogRotationAction: Sendable {
    case refresh
    case setEnabled(Bool)
    case setMaximumSize(Int)
    case setGenerations(Int)
    case receive(Result<LogRotationStatus, SettingsFailure>)
}
