import Foundation
import NanoRedux

extension ServicesReducer {
    func reduceCopyFeedback(
        into state: inout ServicesState, action: ServicesCopyFeedbackAction,
    ) -> Effect<ServicesCopyFeedbackAction> {
        switch action {
        case let .copyValue(value, item, identifier):
            let id = UUID()
            state.copyRequestID = id
            state.copyToast = nil
            let clipboardClient = dependencies.clipboardClient
            return .run(lifetime: .replaceable("services.copy")) {
                let succeeded = await clipboardClient.copy(value)
                return .receiveCopyValue(CopyToast(id: id, identifier: identifier, item: item, succeeded: succeeded))
            }

        case let .receiveCopyValue(toast):
            guard state.copyRequestID == toast.id else { return .none }
            state.copyToast = toast
            let sleep = dependencies.sleepForCopyToast
            return .run(lifetime: .replaceable("services.copyToast")) {
                do {
                    try await sleep(.milliseconds(1500))
                    return .dismissCopyToast(toast.id)
                } catch {
                    return nil
                }
            }

        case let .dismissCopyToast(id):
            guard state.copyToast?.id == id else { return .none }
            state.copyToast = nil
            state.copyRequestID = nil
            return .none

        case .clearCopyFeedback:
            state.copyRequestID = nil
            state.copyToast = nil
            return .none
        }
    }
}
