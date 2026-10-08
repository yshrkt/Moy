import Foundation

public actor DefaultServiceManagementUseCase: ServiceManagementUseCase {
    private let serviceRepository: any ServiceRepository
    private let launchAgentRepository: any LaunchAgentRepository

    public init(
        serviceRepository: any ServiceRepository,
        launchAgentRepository: any LaunchAgentRepository,
    ) {
        self.serviceRepository = serviceRepository
        self.launchAgentRepository = launchAgentRepository
    }

    public func list() async throws -> [ServiceDefinition] {
        try await serviceRepository.list()
    }

    public func find(identifier: ServiceIdentifier) async throws -> ServiceDefinition {
        try await serviceRepository.find(identifier: identifier)
    }

    public func create(_ service: ServiceDraft, enable: Bool = false) async throws -> ServiceDefinition {
        let created = try await serviceRepository.create(service)
        guard enable else { return created }
        do {
            try await launchAgentRepository.enable(created)
            return created
        } catch {
            try? await serviceRepository.remove(identifier: created.identifier)
            throw error
        }
    }

    public func update(_ service: ServiceDefinition) async throws {
        let identifier = service.identifier
        let previous = try await serviceRepository.find(identifier: identifier)
        try await serviceRepository.update(service)
        guard !service.hasSameLaunchConfiguration(as: previous) else { return }

        do {
            let currentStatus = try await launchAgentRepository.status(identifier: identifier)
            guard currentStatus.registration != .disabled else { return }
            try await launchAgentRepository.disable(identifier: identifier)
            try await launchAgentRepository.enable(service)
            if case .running = currentStatus.runtime {
                try await launchAgentRepository.restart(identifier: identifier)
            }
        } catch {
            throw MoyError.serviceUpdateNotApplied(
                identifier: identifier.rawValue,
                reason: error.localizedDescription,
            )
        }
    }

    public func remove(identifier: ServiceIdentifier) async throws {
        _ = try await serviceRepository.find(identifier: identifier)
        let currentStatus = try await launchAgentRepository.status(identifier: identifier)
        if currentStatus.registration != .disabled {
            try await launchAgentRepository.disable(identifier: identifier)
        }
        try await serviceRepository.remove(identifier: identifier)
    }

    public func enable(identifier: ServiceIdentifier) async throws {
        let service = try await serviceRepository.find(identifier: identifier)
        try await launchAgentRepository.enable(service)
    }

    public func disable(identifier: ServiceIdentifier) async throws {
        _ = try await serviceRepository.find(identifier: identifier)
        try await launchAgentRepository.disable(identifier: identifier)
    }

    public func restart(identifier: ServiceIdentifier) async throws {
        _ = try await serviceRepository.find(identifier: identifier)
        try await launchAgentRepository.restart(identifier: identifier)
    }

    public func status(identifier: ServiceIdentifier) async throws -> ServiceStatus {
        _ = try await serviceRepository.find(identifier: identifier)
        return try await launchAgentRepository.status(identifier: identifier)
    }

    public func statuses() async throws -> [ServiceStatus] {
        var statuses: [ServiceStatus] = []
        for service in try await list() {
            let status = try await launchAgentRepository.status(identifier: service.identifier)
            statuses.append(status)
        }
        return statuses
    }
}
