import AppKit
import MoyKit
import NanoRedux
import SwiftUI

@MainActor
struct MenuBarServicesView: View {
    private enum Layout {
        static let menuWidth: CGFloat = 280
        static let maximumVisibleServiceCount = 8
        static let sectionHeaderHeight: CGFloat = 28
        static let serviceRowHeight: CGFloat = 40
        static let actionButtonSize: CGFloat = 24
    }

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
        .frame(width: Layout.menuWidth)
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
            RefreshButton {
                store.send(.refreshServices)
            }
            .buttonStyle(.plain)
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
                ForEach(store.state.serviceSections) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(section.kind.localizedName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: Layout.sectionHeaderHeight, alignment: .leading)
                        ForEach(section.services) { service in
                            serviceMenu(service)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: serviceListHeight)
        .scrollIndicators(.visible)
        .scrollIndicatorsFlash(onAppear: true)
        .scrollIndicatorsFlash(trigger: store.state.services.count > Layout.maximumVisibleServiceCount)
    }

    private func serviceMenu(_ service: ServiceDefinition) -> some View {
        let status = store.state.statuses[service.identifier]
        let presentation = ServiceStatusPresentation(
            status: status,
            hasError: store.state.statusFailures.contains(service.identifier),
        )
        let isOperating = store.state.isOperating(service.identifier)

        return HStack(spacing: 10) {
            ServiceStatusIndicator(presentation: presentation)
            Text(service.name)
                .lineLimit(1)
            Spacer()
            if isOperating {
                ProgressView()
                    .controlSize(.small)
            }

            Menu {
                Button(L10n.Common.details) {
                    showDetails(for: service)
                }

                Divider()
                serviceOperations(service, status: status, isOperating: isOperating)
                logsMenu(service)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: Layout.actionButtonSize, height: Layout.actionButtonSize)
                    .background {
                        Circle()
                            .fill(.quaternary)
                    }
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help(L10n.Common.actions)
            .accessibilityLabel(L10n.Common.actions)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: Layout.serviceRowHeight, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func serviceOperations(
        _ service: ServiceDefinition,
        status: ServiceStatus?,
        isOperating: Bool,
    ) -> some View {
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

    private func logsMenu(_ service: ServiceDefinition) -> some View {
        Section(L10n.Services.logs) {
            logMenu(L10n.Services.standardOut, path: service.standardOutPath)
            logMenu(L10n.Services.standardError, path: service.standardErrorPath)
        }
    }

    private func logMenu(_ title: String, path: String) -> some View {
        Menu(title) {
            Button(L10n.Common.open) {
                store.send(.openLog(path))
            }
            Button(L10n.Common.reveal) {
                store.send(.revealLog(path))
            }
        }
    }

    private var serviceListHeight: CGFloat {
        CGFloat(min(store.state.services.count, Layout.maximumVisibleServiceCount)) * Layout.serviceRowHeight
            + CGFloat(store.state.serviceSections.count) * Layout.sectionHeaderHeight
    }

    private func showDetails(for service: ServiceDefinition) {
        store.send(.selectService(service.identifier))
        openWindow(id: MoyWindow.management)
        NSApplication.shared.activate(ignoringOtherApps: true)
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
