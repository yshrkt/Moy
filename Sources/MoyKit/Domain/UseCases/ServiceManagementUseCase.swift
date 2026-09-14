public protocol ServiceManagementUseCase: Sendable {
    func list() async throws -> [ServiceDefinition]
    func find(identifier: ServiceIdentifier) async throws -> ServiceDefinition
    func create(_ service: ServiceDraft, enable: Bool) async throws -> ServiceDefinition
    func update(_ service: ServiceDefinition) async throws
    func remove(identifier: ServiceIdentifier) async throws
    func enable(identifier: ServiceIdentifier) async throws
    func disable(identifier: ServiceIdentifier) async throws
    func restart(identifier: ServiceIdentifier) async throws
    func status(identifier: ServiceIdentifier) async throws -> ServiceStatus
    func statuses() async throws -> [ServiceStatus]
}
