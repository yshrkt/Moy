import NanoRedux
import SwiftUI

@MainActor
struct ServiceManagementView: View {
    let store: ServicesStore

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            if let service = store.state.selectedService {
                ServiceDetailView(store: store, service: service)
                    .id(service.identifier)
            } else {
                ContentUnavailableView(
                    L10n.Services.noSelection,
                    systemImage: "terminal",
                )
            }
        }
        .navigationTitle(L10n.Services.title)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.send(.refreshServices)
                } label: {
                    Label(L10n.Common.refresh, systemImage: "arrow.clockwise")
                }
                .disabled(store.state.isLoading)

                Button {
                    store.send(.presentCreateService)
                } label: {
                    Label(L10n.Common.add, systemImage: "plus")
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { store.state.editor != nil },
                set: { isPresented in
                    if !isPresented {
                        store.send(.dismissEditor)
                    }
                },
            ),
        ) {
            ServiceEditorView(store: store)
        }
        .alert(
            L10n.Services.deleteTitle,
            isPresented: Binding(
                get: { store.state.pendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        store.send(.cancelDeleteService)
                    }
                },
            ),
        ) {
            Button(L10n.Common.cancel, role: .cancel) {
                store.send(.cancelDeleteService)
            }
            Button(L10n.Common.delete, role: .destructive) {
                store.send(.confirmDeleteService)
            }
        } message: {
            Text(L10n.Services.deleteMessage)
        }
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
        .task {
            store.send(.appear)
        }
    }

    private var sidebar: some View {
        List(selection: Binding(
            get: { store.state.selectedIdentifier },
            set: { store.send(.selectService($0)) },
        )) {
            ForEach(store.state.services) { service in
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.name)
                        .fontWeight(.medium)
                    Text(service.identifier.rawValue)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    ServiceStatusView(
                        status: store.state.statuses[service.identifier],
                        statusUnavailable: store.state.statusFailures.contains(service.identifier),
                    )
                }
                .padding(.vertical, 3)
                .tag(service.identifier)
            }
        }
        .overlay {
            if store.state.services.isEmpty {
                ContentUnavailableView(
                    store.state.isLoading ? L10n.Services.loading : L10n.Menu.empty,
                    systemImage: "terminal",
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            cliInstaller
        }
    }

    private var cliInstaller: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.state.cliInstallationPath != nil {
                Label(L10n.Services.cliInstalled, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Button {
                    store.send(.installCLI)
                } label: {
                    if store.state.isInstallingCLI {
                        Label(L10n.Services.installingCLI, systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    } else {
                        Label(L10n.Services.installCLI, systemImage: "terminal")
                    }
                }
                .disabled(store.state.isInstallingCLI)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.bar)
    }
}
