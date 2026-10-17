enum SettingsAction: Sendable {
    case launchAtLogin(LaunchAtLoginAction)
    case cli(CLIAction)
    case logRotation(LogRotationAction)
    case appear
    case selectTab(SettingsTab)
    case dismissFailure
}
