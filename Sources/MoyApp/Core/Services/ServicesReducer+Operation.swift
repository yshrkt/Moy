import MoyKit
import NanoRedux

extension ServicesReducer {
    func reduceOperation(
        into state: inout ServicesState, action: ServicesOperationAction,
    ) -> Effect<ServicesAction> {
        switch action {
        case let .enable(identifier):
            return serviceOperation(into: &state, identifier: identifier) {
                try await dependencies.serviceManagementUseCase.enable(identifier: identifier)
            }

        case let .disable(identifier):
            return serviceOperation(into: &state, identifier: identifier) {
                try await dependencies.serviceManagementUseCase.disable(identifier: identifier)
            }

        case let .restart(identifier):
            return serviceOperation(into: &state, identifier: identifier) {
                try await dependencies.serviceManagementUseCase.restart(identifier: identifier)
            }

        case let .receive(identifier, .success):
            state.operatingIdentifiers.remove(identifier)
            return .run { .refreshServices }

        case let .receive(identifier, .failure(failure)):
            state.operatingIdentifiers.remove(identifier)
            state.failure = failure == .cancelled ? nil : failure
            return .run { .refreshServices }
        }
    }

    private func serviceOperation(
        into state: inout ServicesState,
        identifier: ServiceIdentifier,
        operation: @escaping @Sendable () async throws -> Void,
    ) -> Effect<ServicesAction> {
        guard !state.operatingIdentifiers.contains(identifier) else { return .none }
        state.operatingIdentifiers.insert(identifier)
        return .run {
            do {
                try await operation()
                return .operation(.receive(identifier, .success(())))
            } catch {
                return .operation(.receive(identifier, .failure(.from(error))))
            }
        }
    }
}
