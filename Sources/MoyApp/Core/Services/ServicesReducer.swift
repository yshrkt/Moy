import Foundation
import MoyKit
import NanoRedux

struct ServicesReducer: InjectableReducer {
    private enum EffectID {
        static let refresh = "services.refresh"
    }

    let dependencies: ServicesDependencies

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func reduce(
        into state: inout ServicesState,
        action: ServicesAction,
    ) -> Effect<ServicesAction> {
        switch action {
        case .appear, .refreshServices:
            state.isLoading = true
            let serviceManagementUseCase = dependencies.serviceManagementUseCase
            return .run(lifetime: .replaceable(EffectID.refresh)) {
                do {
                    let services = try await serviceManagementUseCase.list()
                    var statuses: [ServiceIdentifier: ServiceStatus] = [:]
                    var statusFailures: Set<ServiceIdentifier> = []
                    for service in services {
                        do {
                            statuses[service.identifier] = try await serviceManagementUseCase.status(
                                identifier: service.identifier,
                            )
                        } catch {
                            statusFailures.insert(service.identifier)
                        }
                    }
                    return .receiveServices(.success(.init(
                        services: services,
                        statuses: statuses,
                        statusFailures: statusFailures,
                    )))
                } catch {
                    return .receiveServices(.failure(.from(error)))
                }
            }

        case let .receiveServices(.success(snapshot)):
            state.isLoading = false
            state.services = snapshot.services
            var validationEffect: Effect<ServicesAction> = .none
            if var editor = state.editor {
                validationEffect = ServiceEditorReducer(dependencies: dependencies.editor)
                    .reduce(into: &editor, action: .updateExistingIdentifiers(
                        Set(snapshot.services.map(\.identifier.rawValue)),
                    ))
                    .map(namespace: Self.self) { .editor($0) }
            }
            state.statuses = snapshot.statuses
            state.statusFailures = snapshot.statusFailures
            if let selectedIdentifier = state.selectedIdentifier,
               snapshot.services.contains(where: { $0.identifier == selectedIdentifier })
            {
                return validationEffect
            }
            state.selectedIdentifier = snapshot.services.first?.identifier
            state.copyRequestID = nil
            state.copyToast = nil
            return validationEffect

        case let .receiveServices(.failure(failure)):
            state.isLoading = false
            state.failure = failure
            return .none

        case let .selectService(identifier):
            if state.selectedIdentifier != identifier {
                state.copyRequestID = nil
                state.copyToast = nil
            }
            state.selectedIdentifier = identifier
            return .none

        case .presentCreateService:
            guard state.canOpenEditor else { return .none }
            state.failure = nil
            state.editor = .create(existingIdentifiers: Set(state.services.map(\.identifier.rawValue)))
            return .none

        case let .presentEditService(identifier):
            guard state.canOpenEditor else { return .none }
            guard let service = state.services.first(where: { $0.identifier == identifier }) else {
                return .none
            }
            state.failure = nil
            state.editor = ServiceEditorState(service: service)
            return .none

        case let .transfer(action):
            return reduceTransfer(into: &state, action: action)
                .map(namespace: Self.self) { .transfer($0) }

        case let .editor(.delegate(.cancel(sessionID))):
            guard let editor = state.editor, editor.id == sessionID, !editor.isSaving else { return .none }
            state.editor = nil
            return .none

        case let .editor(.delegate(.save(sessionID, payload))):
            guard let editor = state.editor, editor.id == sessionID, editor.isSaving else { return .none }
            let serviceManagementUseCase = dependencies.serviceManagementUseCase
            return .run {
                do {
                    switch payload {
                    case let .create(identifier, draft):
                        _ = try await serviceManagementUseCase.create(draft, enable: false)
                        return .receiveSave(sessionID, identifier, .success(()))
                    case let .update(definition):
                        try await serviceManagementUseCase.update(definition)
                        return .receiveSave(sessionID, definition.identifier, .success(()))
                    }
                } catch {
                    return .receiveSave(sessionID, payload.identifier, .failure(.from(error)))
                }
            }

        case let .editor(action):
            guard var editor = state.editor else { return .none }
            return ServiceEditorReducer(dependencies: dependencies.editor)
                .reduce(into: &editor, action: action)
                .map(namespace: Self.self) { .editor($0) }

        case let .receiveSave(sessionID, identifier, result):
            guard var editor = state.editor, editor.id == sessionID else { return .none }
            _ = ServiceEditorReducer(dependencies: dependencies.editor)
                .reduce(into: &editor, action: .receiveSave(result))
            if case .success = result {
                state.editor = nil
                state.selectedIdentifier = identifier
                return .run { .refreshServices }
            }
            if case let .failure(.moy(error)) = result, case .serviceUpdateNotApplied = error {
                state.editor = nil
                state.selectedIdentifier = identifier
                state.failure = .moy(error)
                return .run { .refreshServices }
            }
            return .none

        case let .enableService(identifier):
            return serviceOperation(into: &state, identifier: identifier) {
                try await dependencies.serviceManagementUseCase.enable(identifier: identifier)
            }

        case let .disableService(identifier):
            return serviceOperation(into: &state, identifier: identifier) {
                try await dependencies.serviceManagementUseCase.disable(identifier: identifier)
            }

        case let .restartService(identifier):
            return serviceOperation(into: &state, identifier: identifier) {
                try await dependencies.serviceManagementUseCase.restart(identifier: identifier)
            }

        case let .receiveServiceOperation(identifier, .success):
            state.operatingIdentifiers.remove(identifier)
            return .run { .refreshServices }

        case let .receiveServiceOperation(identifier, .failure(failure)):
            state.operatingIdentifiers.remove(identifier)
            state.failure = failure
            return .run { .refreshServices }

        case let .requestDeleteService(identifier):
            state.pendingDeletion = identifier
            return .none

        case .cancelDeleteService:
            state.pendingDeletion = nil
            return .none

        case .confirmDeleteService:
            guard let identifier = state.pendingDeletion,
                  !state.operatingIdentifiers.contains(identifier)
            else {
                return .none
            }
            state.pendingDeletion = nil
            state.operatingIdentifiers.insert(identifier)
            let serviceManagementUseCase = dependencies.serviceManagementUseCase
            return .run {
                do {
                    try await serviceManagementUseCase.remove(identifier: identifier)
                    return .receiveDeleteService(identifier, .success(()))
                } catch {
                    return .receiveDeleteService(identifier, .failure(.from(error)))
                }
            }

        case let .receiveDeleteService(identifier, .success):
            state.operatingIdentifiers.remove(identifier)
            if state.selectedIdentifier == identifier {
                state.selectedIdentifier = nil
            }
            return .run { .refreshServices }

        case let .receiveDeleteService(identifier, .failure(failure)):
            state.operatingIdentifiers.remove(identifier)
            state.failure = failure
            return .run { .refreshServices }

        case let .openLog(path):
            let workspaceClient = dependencies.workspaceClient
            return .run {
                do {
                    try await workspaceClient.open(path)
                    return .receiveFileOperation(.success(()))
                } catch {
                    return .receiveFileOperation(.failure(.from(error)))
                }
            }

        case let .revealLog(path):
            let workspaceClient = dependencies.workspaceClient
            return .run {
                do {
                    try await workspaceClient.reveal(path)
                    return .receiveFileOperation(.success(()))
                } catch {
                    return .receiveFileOperation(.failure(.from(error)))
                }
            }

        case .receiveFileOperation(.success):
            return .none

        case let .receiveFileOperation(.failure(failure)):
            state.failure = failure
            return .none

        case .dismissFailure:
            state.failure = nil
            return .none

        case let .copyFeedback(action):
            return reduceCopyFeedback(into: &state, action: action)
                .map(namespace: Self.self) { .copyFeedback($0) }
        }
    }
}

private extension ServicesReducer {
    func serviceOperation(
        into state: inout ServicesState,
        identifier: ServiceIdentifier,
        operation: @escaping @Sendable () async throws -> Void,
    ) -> Effect<ServicesAction> {
        guard !state.operatingIdentifiers.contains(identifier) else { return .none }
        state.operatingIdentifiers.insert(identifier)
        return .run {
            do {
                try await operation()
                return .receiveServiceOperation(identifier, .success(()))
            } catch {
                return .receiveServiceOperation(identifier, .failure(.from(error)))
            }
        }
    }
}
