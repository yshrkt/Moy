import AppKit
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
        .navigationTitle("")
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
                get: { store.state.editor == nil && store.state.failure != nil },
                set: { isPresented in
                    if !isPresented, store.state.editor == nil {
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
                        hasStatusError: store.state.statusFailures.contains(service.identifier),
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
            sidebarBottomBar
        }
    }

    private var sidebarBottomBar: some View {
        HStack(spacing: 12) {
            RefreshButton {
                store.send(.refreshServices)
            }
            .buttonStyle(.borderless)
            .disabled(store.state.isLoading)

            Spacer()

            Button {
                store.send(.presentCreateService)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help(L10n.Common.add)
            .accessibilityLabel(L10n.Common.add)
        }
        .padding(10)
    }
}
