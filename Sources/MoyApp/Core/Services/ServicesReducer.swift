import Foundation
import MoyKit
import NanoRedux

/// The central reducer intentionally keeps the exhaustive action routing in one switch.
struct ServicesReducer: InjectableReducer {
    private enum EffectID {
        static let refresh = "services.refresh"
        static let choosePath = "services.choosePath"
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
            state.statuses = snapshot.statuses
            state.statusFailures = snapshot.statusFailures
            if let selectedIdentifier = state.selectedIdentifier,
               snapshot.services.contains(where: { $0.identifier == selectedIdentifier })
            {
                return .none
            }
            state.selectedIdentifier = snapshot.services.first?.identifier
            state.copyRequestID = nil
            state.copyToast = nil
            return .none

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
            state.failure = nil
            state.editor = .create()
            return .none

        case let .presentEditService(identifier):
            guard let service = state.services.first(where: { $0.identifier == identifier }) else {
                return .none
            }
            state.failure = nil
            state.editor = ServiceEditorState(service: service)
            return .none

        case .dismissEditor:
            guard !state.isSaving else { return .none }
            state.editor = nil
            state.failure = nil
            return .none

        case let .updateEditor(field):
            guard var editor = state.editor else { return .none }
            switch field {
            case let .identifier(value):
                guard case .create = editor.mode else { return .none }
                editor.identifier = value
            case let .displayName(value):
                editor.displayName = value
            case let .description(value):
                editor.serviceDescription = value
            case let .executable(value):
                editor.executable = value
            case let .workingDirectory(value):
                editor.workingDirectory = value
            case let .runAtLoad(value):
                editor.runAtLoad = value
            case let .keepAlive(value):
                editor.keepAlive = value
            case let .throttleInterval(value):
                editor.throttleInterval = value
            case let .standardOutPath(value):
                editor.standardOutPath = value
            case let .standardErrorPath(value):
                editor.standardErrorPath = value
            }
            state.editor = editor
            return .none

        case .selectArgument, .moveArgument, .dropArgument, .addArgument, .updateArgument, .removeArgument,
             .selectEnvironmentVariable, .addEnvironmentVariable, .updateEnvironmentKey,
             .updateEnvironmentValue, .removeEnvironmentVariable:
            reduceEditorList(into: &state, action: action)
            return .none

        case let .chooseEditorPath(path):
            let filePanelClient = dependencies.filePanelClient
            return .run(lifetime: .replaceable(EffectID.choosePath)) {
                let selectedPath = await filePanelClient.choosePath(path)
                return .receiveEditorPath(path, selectedPath)
            }

        case let .receiveEditorPath(path, selectedPath):
            guard let selectedPath else { return .none }
            let field: ServiceEditorField = switch path {
            case .executable: .executable(selectedPath)
            case .workingDirectory: .workingDirectory(selectedPath)
            case .standardOut: .standardOutPath(selectedPath)
            case .standardError: .standardErrorPath(selectedPath)
            }
            return .run { .updateEditor(field) }

        case let .saveService(enable):
            guard !state.isSaving, let editor = state.editor else { return .none }
            state.failure = nil
            let payload: ServiceEditorPayload
            do {
                payload = try ServiceEditorPayload(editor: editor)
            } catch {
                state.failure = .from(error)
                return .none
            }
            state.isSaving = true
            let serviceManagementUseCase = dependencies.serviceManagementUseCase
            return .run {
                do {
                    switch payload {
                    case let .create(identifier, draft):
                        _ = try await serviceManagementUseCase.create(draft, enable: enable)
                        return .receiveSave(identifier, .success(()))
                    case let .update(definition):
                        try await serviceManagementUseCase.update(definition)
                        return .receiveSave(definition.identifier, .success(()))
                    }
                } catch {
                    return .receiveSave(payload.identifier, .failure(.from(error)))
                }
            }

        case let .receiveSave(identifier, .success):
            state.isSaving = false
            state.editor = nil
            state.selectedIdentifier = identifier
            return .run { .refreshServices }

        case let .receiveSave(_, .failure(failure)):
            state.isSaving = false
            state.failure = failure
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

        case .copyValue, .receiveCopyValue, .dismissCopyToast, .clearCopyFeedback:
            return reduceCopyFeedback(into: &state, action: action)
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
