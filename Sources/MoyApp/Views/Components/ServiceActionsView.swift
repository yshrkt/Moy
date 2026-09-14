import MoyKit
import NanoRedux
import SwiftUI

typealias ServicesStore = Store<ServicesState, ServicesAction>

struct ServiceActionsView: View {
    let store: ServicesStore
    let service: ServiceDefinition
    var compact = false

    var body: some View {
        if compact {
            actions
                .buttonStyle(.borderless)
        } else {
            actions
                .buttonStyle(.bordered)
        }
    }

    private var actions: some View {
        let status = store.state.statuses[service.identifier]
        let isOperating = store.state.isOperating(service.identifier)

        return HStack(spacing: 8) {
            if isOperating {
                ProgressView()
                    .controlSize(.small)
            }

            if status?.allowsEnable == true {
                Button(L10n.Common.enable) {
                    store.send(.enableService(service.identifier))
                }
                .disabled(isOperating)
            }

            if status?.allowsDisable == true {
                Button(L10n.Common.disable) {
                    store.send(.disableService(service.identifier))
                }
                .disabled(isOperating)
            }

            if status?.allowsRestart == true {
                Button(L10n.Common.restart) {
                    store.send(.restartService(service.identifier))
                }
                .disabled(isOperating)
            }
        }
    }
}
