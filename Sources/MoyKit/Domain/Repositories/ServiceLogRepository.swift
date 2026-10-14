public protocol ServiceLogRepository: Sendable {
    func prepare(for service: ServiceDefinition) async throws
}
