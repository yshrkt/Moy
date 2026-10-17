import NanoRedux

extension ServicesReducer {
    func reduceDeletion(
        into state: inout ServicesState, action: ServicesDeletionAction,
    ) -> Effect<ServicesAction> {
        switch action {
        case let .request(identifier):
            state.pendingDeletion = identifier
            return .none

        case .cancel:
            state.pendingDeletion = nil
            return .none

        case .confirm:
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
                    return .deletion(.receive(identifier, .success(())))
                } catch {
                    return .deletion(.receive(identifier, .failure(.from(error))))
                }
            }

        case let .receive(identifier, .success):
            state.operatingIdentifiers.remove(identifier)
            if state.selectedIdentifier == identifier {
                state.selectedIdentifier = nil
            }
            return .run { .refreshServices }

        case let .receive(identifier, .failure(failure)):
            state.operatingIdentifiers.remove(identifier)
            state.failure = failure == .cancelled ? nil : failure
            return .run { .refreshServices }
        }
    }
}
