/// Keeps the elevated operation bound to the definition reviewed before authentication.
/// JSON updates still compare the original value under the repository's file lock.
public struct ReviewedServiceRepository: ServiceRepository {
    public let base: any ServiceRepository
    public let expected: ServiceDefinition

    public init(base: any ServiceRepository, expected: ServiceDefinition) {
        self.base = base
        self.expected = expected
    }

    public func list() async throws -> [ServiceDefinition] {
        try await base.list()
    }

    public func find(identifier: ServiceIdentifier) async throws -> ServiceDefinition {
        guard identifier == expected.identifier,
              try await base.find(identifier: identifier) == expected else { throw MoyError.serviceChanged }
        return expected
    }

    public func create(_: ServiceDraft) async throws -> ServiceDefinition {
        throw MoyError.serviceChanged
    }

    public func update(_ service: ServiceDefinition) async throws {
        try await base.update(service, expected: expected)
    }

    public func update(_ service: ServiceDefinition, expected: ServiceDefinition) async throws {
        guard expected == self.expected else { throw MoyError.serviceChanged }
        try await base.update(service, expected: expected)
    }

    public func remove(identifier: ServiceIdentifier) async throws {
        _ = try await find(identifier: identifier)
        try await base.remove(identifier: identifier)
    }
}
