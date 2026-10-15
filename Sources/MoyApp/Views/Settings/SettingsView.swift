import AppKit
import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase

    let store: SettingsStore

    var body: some View {
        let backgroundColor = Color(nsColor: .windowBackgroundColor)

        return TabView(selection: Binding(
            get: { store.state.selectedTab },
            set: { store.send(.selectTab($0)) },
        )) {
            SettingsContentView(store: store)
                .tabItem { Label(L10n.Settings.title, systemImage: "gearshape") }
                .tag(SettingsTab.settings)

            SettingsInformationView()
                .tabItem { Label(L10n.Settings.information, systemImage: "info.circle") }
                .tag(SettingsTab.information)
        }
        .tabViewStyle(.tabBarOnly)
        .toolbarBackground(backgroundColor, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .frame(width: 560, height: 440)
        .background(backgroundColor)
        .containerBackground(backgroundColor, for: .window)
        .task {
            store.send(.appear)
            store.send(.refreshLaunchAtLoginStatus)
            store.send(.logRotation(.refresh))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.send(.refreshCLIStatus)
                store.send(.refreshLaunchAtLoginStatus)
                store.send(.logRotation(.refresh))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // A menu bar app's scenePhase may stay active while Finder has focus.
            store.send(.refreshCLIStatus)
            store.send(.refreshLaunchAtLoginStatus)
            store.send(.logRotation(.refresh))
        }
        .alert(
            L10n.Settings.uninstallCLITitle,
            isPresented: Binding(
                get: { store.state.isConfirmingCLIUninstallation },
                set: {
                    if !$0 {
                        store.send(.dismissCLIUninstallation)
                    }
                },
            ),
        ) {
            Button(L10n.Settings.confirmUninstallCLI, role: .destructive) { store.send(.uninstallCLI) }
            Button(L10n.Common.cancel, role: .cancel) { store.send(.dismissCLIUninstallation) }
        } message: {
            Text(L10n.Settings.uninstallCLIMessage)
        }
        .alert(
            L10n.Common.error,
            isPresented: Binding(
                get: { store.state.failure != nil },
                set: {
                    if !$0 {
                        store.send(.dismissFailure)
                    }
                },
            ),
        ) {
            Button(L10n.Common.ok) { store.send(.dismissFailure) }
        } message: {
            Text(store.state.failure?.localizedMessage ?? "")
        }
    }
}

#if DEBUG
    #Preview {
        SettingsView(store: .reducer(
            initialState: SettingsState(),
            reducer: SettingsReducer(dependencies: SettingsDependencies(
                cliInstallerClient: CLIInstallerClient(status: { .notInstalled }, install: {}, uninstall: {}),
            )),
        ))
    }
#endif
