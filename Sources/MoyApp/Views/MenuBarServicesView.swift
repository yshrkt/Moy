import AppKit
import NanoRedux
import SwiftUI

@MainActor
struct MenuBarServicesView: View {
    @Environment(\.openWindow) private var openWindow

    let store: ServicesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.state.services.isEmpty {
                emptyState
            } else {
                services
            }

            Divider()
            footer
        }
        .frame(width: 380)
        .task {
            store.send(.appear)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                store.send(.refreshServices)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(L10n.Menu.title)
                .font(.headline)
            Spacer()
            if store.state.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                store.send(.refreshServices)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help(L10n.Common.refresh)
            .accessibilityLabel(L10n.Common.refresh)
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(store.state.isLoading ? L10n.Services.loading : L10n.Menu.empty)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var services: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.state.services) { service in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
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
                            Spacer()
                            ServiceActionsView(store: store, service: service, compact: true)
                        }

                        Menu(L10n.Services.logs) {
                            Button("\(L10n.Services.standardOut) — \(L10n.Common.open)") {
                                store.send(.openLog(service.standardOutPath))
                            }
                            Button("\(L10n.Services.standardOut) — \(L10n.Common.reveal)") {
                                store.send(.revealLog(service.standardOutPath))
                            }
                            Divider()
                            Button("\(L10n.Services.standardError) — \(L10n.Common.open)") {
                                store.send(.openLog(service.standardErrorPath))
                            }
                            Button("\(L10n.Services.standardError) — \(L10n.Common.reveal)") {
                                store.send(.revealLog(service.standardErrorPath))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .padding(12)
                    Divider()
                }
            }
        }
        .frame(maxHeight: 420)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Button {
                openWindow(id: MoyWindow.management)
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label(L10n.Menu.manage, systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Button {
                openWindow(id: MoyWindow.settings)
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label(L10n.Settings.open, systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text(L10n.Common.quit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}
