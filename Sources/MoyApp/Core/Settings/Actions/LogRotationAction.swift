import MoyKit

enum LogRotationAction: Sendable {
    case refresh
    case setEnabled(Bool)
    case setMaximumSize(Int)
    case setGenerations(Int)
    case receive(Result<LogRotationStatus, SettingsFailure>)
}
