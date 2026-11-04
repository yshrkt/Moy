import MoyKit
import NanoRedux
import SwiftUI

@MainActor
struct ServiceDetailView: View {
    @Environment(\.openWindow) private var openWindow

    let store: ServicesStore
    let service: ServiceDefinition

    var body: some View {
        ScrollView {
            detailContent
        }
        .background {
            WindowVisibilityObserver { visible in
                store.send(.metrics(.setVisibility(service.identifier, visible)))
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.state.copyToast, !toast.succeeded, toast.identifier == service.identifier {
                CopyToastView(toast: toast)
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .onDisappear {
            store.send(.copyFeedback(.clear))
            store.send(.metrics(.setVisibility(service.identifier, false)))
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.send(.presentEditService(service.identifier))
                } label: {
                    Label(L10n.Common.edit, systemImage: "pencil")
                }
                .disabled(!store.state.canOpenEditor)
                Button {
                    store.send(.transfer(.duplicateService(service.identifier)))
                } label: {
                    Label(L10n.Services.duplicate, systemImage: "plus.square.on.square")
                }
                .disabled(!store.state.canOpenEditor || store.state.isOperating(service.identifier))
                Button {
                    store.send(.transfer(.exportService(service.identifier)))
                } label: {
                    Label(L10n.Services.export, systemImage: "square.and.arrow.up")
                }
                .disabled(!store.state.canOpenEditor || store.state.isOperating(service.identifier))
                Button(role: .destructive) {
                    store.send(.deletion(.request(service.identifier)))
                } label: {
                    Label(L10n.Common.delete, systemImage: "trash")
                }
                .disabled(store.state.isOperating(service.identifier))
            }

            ToolbarSpacer(.fixed)

            ToolbarItemGroup {
                Button {
                    openWindow(id: MoyWindow.settings)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                } label: {
                    Label(L10n.Settings.title, systemImage: "gearshape")
                }
                .help(L10n.Settings.title)
                .accessibilityLabel(L10n.Settings.title)
            }
        }
    }

    var detailContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            Divider()
            ServiceDetailStatusView(store: store, service: service)
            identitySection
            configurationSection
            behaviorSection
            logsSection
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identitySection: some View {
        DetailSection(title: L10n.Services.identity) {
            DetailRow("Label") {
                copyableValue(service.identifier.launchdLabel, item: "Label")
            }
        }
    }

    private var configurationSection: some View {
        DetailSection(title: L10n.Services.executionSettings) {
            DetailRow("ProgramArguments") {
                let command = CommandLineFormatter.format(service.programArguments)
                copyableValue(command, item: "ProgramArguments")
            }
            if let workingDirectory = service.workingDirectory, !workingDirectory.isEmpty {
                sectionDivider
                DetailRow("WorkingDirectory") {
                    copyableValue(workingDirectory, item: "WorkingDirectory")
                }
            }
            if !service.environmentVariables.isEmpty {
                sectionDivider
                DetailRow("EnvironmentVariables") {
                    copyableValue(service.environmentVariables.sorted(by: { $0.key < $1.key })
                        .map { "\($0.key)=\($0.value)" }
                        .joined(separator: "\n"), item: "EnvironmentVariables")
                }
            }
        }
    }

    private var behaviorSection: some View {
        DetailSection(title: L10n.Services.behavior) {
            DetailRow("RunAtLoad") {
                CopyableValue(String(service.runAtLoad))
            }
            sectionDivider
            DetailRow("KeepAlive") {
                CopyableValue(String(service.keepAlive))
            }
            if let throttleInterval = service.throttleInterval {
                sectionDivider
                DetailRow("ThrottleInterval") {
                    CopyableValue(String(throttleInterval))
                }
            }
        }
    }

    private var logsSection: some View {
        DetailSection(title: L10n.Services.logs) {
            logRow(title: "StandardOutPath", path: service.standardOutPath)
            sectionDivider
            logRow(title: "StandardErrorPath", path: service.standardErrorPath)
        }
    }

    private func logRow(title: String, path: String) -> some View {
        DetailRow(title) {
            VStack(alignment: .leading, spacing: 7) {
                copyableValue(path, item: title)
                HStack {
                    Button(L10n.Common.open) {
                        store.send(.openLog(path))
                    }
                    Button(L10n.Common.reveal) {
                        store.send(.revealLog(path))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var sectionDivider: some View {
        Divider()
            .gridCellUnsizedAxes(.horizontal)
    }

    private func copyableValue(_ value: String, item: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CopyableValue(value)
                .frame(maxWidth: .infinity, alignment: .leading)
            copyButton(item: item, value: value)
        }
    }

    private func copyButton(item: String, value: String) -> some View {
        CopyValueButton(store: store, identifier: service.identifier, item: item, value: value)
    }
}

struct CopyToastView: View {
    let toast: CopyToast

    var body: some View {
        Text(toast.succeeded ? L10n.Services.copiedItem(toast.item) : L10n.Services.copyItemFailed(toast.item))
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailRow<Content: View>: View {
    let key: String
    @ViewBuilder let content: Content

    init(_ key: String, @ViewBuilder content: () -> Content) {
        self.key = key
        self.content = content()
    }

    var body: some View {
        GridRow(alignment: .top) {
            Text(key)
                .fixedSize(horizontal: true, vertical: false)
                .gridColumnAlignment(.leading)
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .gridColumnAlignment(.leading)
        }
    }
}

private struct CopyableValue: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.body.monospaced())
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension ServiceDetailView {
    private var kindLabel: some View {
        Text(service.kind.localizedName)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.secondary, lineWidth: 1)
            }
            .fixedSize()
    }
}

private extension ServiceDetailView {
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(service.name)
                .font(.largeTitle.bold())
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                kindLabel
                Text(service.identifier.rawValue)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityLabel(L10n.Services.identifier)
                    .accessibilityValue(service.identifier.rawValue)
            }
            if let description = service.description, !description.isEmpty {
                Text(description)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        }
    }
}
