import MoyKit
import NanoRedux
import SwiftUI

enum MoyWindow {
    static let management = "management"
}

@main
struct MoyApp: App {
    @State private var store: ServicesStore

    init() {
        let store = Store.reducer(
            initialState: ServicesState(),
            reducer: ServicesReducer(dependencies: ServicesDependencies(
                serviceManagementUseCase: MoyRuntime.makeServiceManagementUseCase(),
            )),
        )
        _store = State(initialValue: store)
    }

    var body: some Scene {
        Window(L10n.App.name, id: MoyWindow.management) {
            ServiceManagementView(store: store)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 980, height: 680)

        MenuBarExtra(L10n.App.name, systemImage: "terminal") {
            MenuBarServicesView(store: store)
                .alert(
                    L10n.Common.error,
                    isPresented: Binding(
                        get: { store.state.failure != nil },
                        set: { isPresented in
                            if !isPresented {
                                store.send(.dismissFailure)
                            }
                        },
                    ),
                ) {
                    Button(L10n.Common.ok) {
                        store.send(.dismissFailure)
                    }
                } message: {
                    Text(store.state.failure?.localizedMessage ?? "")
                }
        }
        .menuBarExtraStyle(.window)
    }
}
