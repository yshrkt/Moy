public protocol LaunchAtLoginUseCase: Sendable {
    func status() async -> LaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) async throws
    func openSystemSettings() async
}
