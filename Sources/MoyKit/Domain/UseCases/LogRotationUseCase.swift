public struct LogRotationStatus: Equatable, Sendable {
    public var settings: LogRotationSettings
    public var failures: [String]

    public init(settings: LogRotationSettings, failures: [String] = []) {
        self.settings = settings
        self.failures = failures
    }
}

public protocol LogRotationUseCase: Sendable {
    func refresh() async throws -> LogRotationStatus
    func update(_ settings: LogRotationSettings) async throws -> LogRotationStatus
}
