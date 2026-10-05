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
                .buttonStyle(OpaqueServiceButtonStyle())
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

private struct OpaqueServiceButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && isEnabled
        let background = Color(white: colorScheme == .dark
            ? (isPressed ? 0.30 : 0.24)
            : (isPressed ? 0.84 : 0.92))

        configuration.label
            .foregroundStyle(isEnabled ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .frame(minHeight: 22)
            .background(background, in: RoundedRectangle(cornerRadius: 5))
            .shadow(color: .black.opacity(0.1), radius: 2.0, x: 0, y: 1)
    }
}
