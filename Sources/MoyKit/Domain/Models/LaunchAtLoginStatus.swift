public enum LaunchAtLoginStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

public enum LaunchAtLoginError: Error, Equatable, Sendable {
    case updateFailed(String)
}
