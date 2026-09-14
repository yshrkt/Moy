public protocol ServiceRepository: Sendable {
    func list() async throws -> [ServiceDefinition]
    func find(identifier: ServiceIdentifier) async throws -> ServiceDefinition
    func create(_ service: ServiceDraft) async throws -> ServiceDefinition
    func update(_ service: ServiceDefinition) async throws
    func remove(identifier: ServiceIdentifier) async throws
}

public protocol LaunchAgentRepository: Sendable {
    func status(identifier: ServiceIdentifier) async throws -> ServiceStatus
    func enable(_ service: ServiceDefinition) async throws
    func disable(identifier: ServiceIdentifier) async throws
    func restart(identifier: ServiceIdentifier) async throws
}
