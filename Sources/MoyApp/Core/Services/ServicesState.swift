import Foundation
import MoyKit
import Observation

@Observable
final class ServicesState {
    var services: [ServiceDefinition] = []
    var statuses: [ServiceIdentifier: ServiceStatus] = [:]
    var statusFailures: Set<ServiceIdentifier> = []
    var selectedIdentifier: ServiceIdentifier?
    var editor: ServiceEditorState?
    var transferOperation: ServiceTransferOperation?

    var canOpenEditor: Bool {
        transferOperation == nil && editor == nil
    }

    var pendingDeletion: ServiceIdentifier?
    var operatingIdentifiers: Set<ServiceIdentifier> = []
    var isLoading = false
    var failure: ServicesFailure?
    var copyRequestID: UUID?
    var copyToast: CopyToast?

    var selectedService: ServiceDefinition? {
        guard let selectedIdentifier else { return nil }
        return services.first { $0.identifier == selectedIdentifier }
    }

    func isOperating(_ identifier: ServiceIdentifier) -> Bool {
        operatingIdentifiers.contains(identifier)
    }
}

struct CopyToast: Equatable, Sendable, Identifiable {
    let id: UUID
    let identifier: ServiceIdentifier
    let item: String
    let succeeded: Bool

    func showsSuccess(for identifier: ServiceIdentifier, item: String) -> Bool {
        succeeded && self.identifier == identifier && self.item == item
    }
}

struct ServicesSnapshot: Equatable, Sendable {
    let services: [ServiceDefinition]
    let statuses: [ServiceIdentifier: ServiceStatus]
    let statusFailures: Set<ServiceIdentifier>
}

enum ServicesFailure: Error, Equatable, Sendable {
    case moy(MoyError)
    case serviceJSON(ServiceJSONError)
    case invalidThrottleInterval
    case emptyEnvironmentKey
    case duplicateEnvironmentKey(String)
    case fileNotFound(String)
    case unexpected(String)

    static func from(_ error: any Error) -> Self {
        if let error = error as? Self {
            return error
        }
        if let error = error as? MoyError {
            return .moy(error)
        }
        if let error = error as? ServiceJSONError {
            return .serviceJSON(error)
        }
        if let error = error as? AppOperationError {
            switch error {
            case let .fileNotFound(path):
                return .fileNotFound(path)
            case let .fileOperation(message):
                return .unexpected(message)
            }
        }
        return .unexpected(error.localizedDescription)
    }
}

enum ServiceTransferOperation: Equatable, Sendable {
    case importService
    case exportService(ServiceIdentifier)
}
