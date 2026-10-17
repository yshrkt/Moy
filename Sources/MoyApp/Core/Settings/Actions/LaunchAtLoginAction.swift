import MoyKit

enum LaunchAtLoginAction: Sendable {
    case refreshStatus
    case receiveStatus(LaunchAtLoginStatus)
    case setEnabled(Bool)
    case receiveUpdate(LaunchAtLoginStatus, SettingsFailure?)
    case openSystemSettings
}
