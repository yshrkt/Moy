import Darwin
import Foundation
import MoyKit

/// Delegates only daemon mutations to the bundled CLI after administrator authentication.
struct AuthorizedServiceManagementUseCase: ServiceManagementUseCase {
    let base: any ServiceManagementUseCase
    var authorization: AdministratorAuthorizationClient = .live
    var executable: URL? = BundledCLI.executableURL()

    func list() async throws -> [ServiceDefinition] {
        try await base.list()
    }

    func find(identifier: ServiceIdentifier) async throws -> ServiceDefinition {
        try await base.find(identifier: identifier)
    }

    func status(identifier: ServiceIdentifier) async throws -> ServiceStatus {
        try await base.status(identifier: identifier)
    }

    func statuses() async throws -> [ServiceStatus] {
        try await base.statuses()
    }

    func create(_ service: ServiceDraft, enable: Bool) async throws -> ServiceDefinition {
        // GUI creation and import save definitions only.
        try await base.create(service, enable: enable)
    }

    func update(_ service: ServiceDefinition) async throws {
        let previous = try await base.find(identifier: service.identifier)
        guard service.kind == previous.kind else { throw MoyError.kindCannotChange }
        if service.kind == .launchDaemon, !service.hasSameLaunchConfiguration(as: previous),
           try await base.status(identifier: service.identifier).registration != .disabled
        {
            try ServiceValidator.validate(service)
            let path = service.programArguments.first ?? ""
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
                throw MoyError.executableNotFound(path)
            }
            guard !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: path) else {
                throw MoyError.executableNotRunnable(path)
            }
            try await perform(.init(action: .update, expected: previous, updated: service))
        } else {
            try await base.update(service)
        }
    }

    func remove(identifier: ServiceIdentifier) async throws {
        let service = try await base.find(identifier: identifier)
        if service.kind == .launchDaemon, try await base.status(identifier: identifier).registration != .disabled {
            try await perform(.init(action: .remove, expected: service))
        } else {
            try await base.remove(identifier: identifier)
        }
    }

    func enable(identifier: ServiceIdentifier) async throws {
        try await operate(.enable, identifier: identifier)
    }

    func disable(identifier: ServiceIdentifier) async throws {
        try await operate(.disable, identifier: identifier)
    }

    func restart(identifier: ServiceIdentifier) async throws {
        try await operate(.restart, identifier: identifier)
    }

    private func operate(_ action: DaemonOperation.Action, identifier: ServiceIdentifier) async throws {
        let service = try await base.find(identifier: identifier)
        if service.kind == .launchDaemon {
            try await perform(.init(action: action, expected: service))
        } else {
            switch action {
            case .enable: try await base.enable(identifier: identifier)
            case .disable: try await base.disable(identifier: identifier)
            case .restart: try await base.restart(identifier: identifier)
            case .remove, .update: preconditionFailure("Unsupported service operation")
            }
        }
    }

    private func perform(_ operation: DaemonOperation) async throws {
        guard let executable, FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw MoyError.operationFailed("Bundled CLI executable not found")
        }
        let payload = try JSONEncoder().encode(operation).base64EncodedString()
        let command = [executable.path, "internal-daemon", String(getuid()), payload]
            .map(AdministratorAuthorizationClient.shellQuote).joined(separator: " ")
        let output = try await authorization.execute(command)
        let result = try JSONDecoder().decode(DaemonOperationResult.self, from: Data(output.utf8))
        if let error = result.error {
            throw error
        }
    }
}
