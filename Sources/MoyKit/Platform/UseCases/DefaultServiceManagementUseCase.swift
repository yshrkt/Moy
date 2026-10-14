import Darwin
import Foundation

public actor DefaultServiceManagementUseCase: ServiceManagementUseCase {
    private let serviceRepository: any ServiceRepository
    private let launchDaemonRepository: any LaunchdRepository
    private let requireAdministrator: @Sendable () throws -> Void
    private let launchAgentRepository: any LaunchdRepository

    public init(
        serviceRepository: any ServiceRepository,
        launchAgentRepository: any LaunchdRepository,
        launchDaemonRepository: (any LaunchdRepository)? = nil,
        requireAdministrator: @escaping @Sendable () throws -> Void = {
            guard geteuid() == 0 else { throw MoyError.administratorRequired }
        },
    ) {
        self.launchDaemonRepository = launchDaemonRepository ?? launchAgentRepository
        self.requireAdministrator = requireAdministrator
        self.serviceRepository = serviceRepository
        self.launchAgentRepository = launchAgentRepository
    }

    private func repository(for service: ServiceDefinition) -> any LaunchdRepository {
        service.kind == .launchDaemon ? launchDaemonRepository : launchAgentRepository
    }

    public func list() async throws -> [ServiceDefinition] {
        try await serviceRepository.list()
    }

    public func find(identifier: ServiceIdentifier) async throws -> ServiceDefinition {
        try await serviceRepository.find(identifier: identifier)
    }

    public func create(_ service: ServiceDraft, enable: Bool = false) async throws -> ServiceDefinition {
        if enable, service.kind == .launchDaemon {
            try requireAdministrator()
        }
        let created = try await serviceRepository.create(service)
        guard enable else { return created }
        do {
            try await repository(for: created).enable(created)
            return created
        } catch {
            try? await serviceRepository.remove(identifier: created.identifier)
            throw error
        }
    }

    public func update(_ service: ServiceDefinition) async throws {
        let identifier = service.identifier
        let previous = try await serviceRepository.find(identifier: identifier)
        guard service.kind == previous.kind else { throw MoyError.kindCannotChange }
        let changed = !service.hasSameLaunchConfiguration(as: previous)
        let launchAgentRepository = repository(for: previous)
        let preflightStatus: ServiceStatus?
        if changed, service.kind == .launchDaemon {
            preflightStatus = try await launchAgentRepository.status(identifier: identifier)
            if service.kind == .launchDaemon, preflightStatus?.registration != .disabled {
                try requireAdministrator()
            }
        } else {
            preflightStatus = nil
        }
        try await serviceRepository.update(service, expected: previous)
        guard changed else { return }

        do {
            let currentStatus: ServiceStatus = if let preflightStatus {
                preflightStatus
            } else {
                try await launchAgentRepository.status(identifier: identifier)
            }
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
        let service = try await serviceRepository.find(identifier: identifier)
        let launchAgentRepository = repository(for: service)
        let currentStatus = try await launchAgentRepository.status(identifier: identifier)
        if currentStatus.registration != .disabled {
            if service.kind == .launchDaemon {
                try requireAdministrator()
            }
            try await launchAgentRepository.disable(identifier: identifier)
        }
        try await serviceRepository.remove(identifier: identifier)
    }

    public func enable(identifier: ServiceIdentifier) async throws {
        let service = try await serviceRepository.find(identifier: identifier)
        if service.kind == .launchDaemon {
            try requireAdministrator()
        }
        try await repository(for: service).enable(service)
    }

    public func disable(identifier: ServiceIdentifier) async throws {
        let service = try await serviceRepository.find(identifier: identifier)
        let launchAgentRepository = repository(for: service)
        if service.kind == .launchDaemon {
            try requireAdministrator()
        }
        try await launchAgentRepository.disable(identifier: identifier)
    }

    public func restart(identifier: ServiceIdentifier) async throws {
        let service = try await serviceRepository.find(identifier: identifier)
        let launchAgentRepository = repository(for: service)
        if service.kind == .launchDaemon {
            try requireAdministrator()
        }
        try await launchAgentRepository.restart(identifier: identifier)
    }

    public func status(identifier: ServiceIdentifier) async throws -> ServiceStatus {
        let service = try await serviceRepository.find(identifier: identifier)
        let launchAgentRepository = repository(for: service)
        return try await launchAgentRepository.status(identifier: identifier)
    }

    public func statuses() async throws -> [ServiceStatus] {
        var statuses: [ServiceStatus] = []
        for service in try await list() {
            let status = try await repository(for: service).status(identifier: service.identifier)
            statuses.append(status)
        }
        return statuses
    }
}
