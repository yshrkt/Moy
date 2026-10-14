import MoyKit
import NanoRedux
import SwiftUI

@MainActor
struct ServiceDetailView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    let store: ServicesStore
    let service: ServiceDefinition

    var body: some View {
        ScrollView {
            detailContent
        }
        .overlay(alignment: .bottom) {
            if let toast = store.state.copyToast, !toast.succeeded, toast.identifier == service.identifier {
                CopyToastView(toast: toast)
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .onDisappear {
            store.send(.copyFeedback(.clearCopyFeedback))
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
                    store.send(.transfer(.exportService(service.identifier)))
                } label: {
                    Label(L10n.Services.export, systemImage: "square.and.arrow.up")
                }
                .disabled(!store.state.canOpenEditor || store.state.isOperating(service.identifier))
                Button(role: .destructive) {
                    store.send(.requestDeleteService(service.identifier))
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
            statusSection
            identitySection
            configurationSection
            behaviorSection
            logsSection
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(service.name)
                .font(.largeTitle.bold())
            Text(service.identifier.rawValue)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .accessibilityLabel(L10n.Services.identifier)
                .accessibilityValue(service.identifier.rawValue)
            if let description = service.description, !description.isEmpty {
                Text(description)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var statusSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                statusDetails
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                statusActions
            }
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    statusDetails
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 10) {
                        statusItems
                    }
                }
                statusActions
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (statusCardColor ?? .clear).opacity(colorScheme == .dark ? 0.08 : 0.10),
            in: RoundedRectangle(cornerRadius: 10),
        )
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    statusCardColor.map { AnyShapeStyle($0.opacity(0.22)) } ?? AnyShapeStyle(.quaternary),
                    lineWidth: 1,
                )
        }
    }

    private var statusPresentation: ServiceStatusPresentation {
        ServiceStatusPresentation(
            status: store.state.statuses[service.identifier],
            hasError: store.state.statusFailures.contains(service.identifier),
        )
    }

    private var statusCardColor: Color? {
        switch statusPresentation {
        case .loading, .disabled: nil
        case .running, .waiting, .needsAttention, .error: statusPresentation.color
        }
    }

    private var statusDetails: some View {
        HStack(spacing: 20) {
            statusItems
        }
    }

    @ViewBuilder
    private var statusItems: some View {
        let status = store.state.statuses[service.identifier]
        let presentation = statusPresentation

        HStack(spacing: 10) {
            ServiceStatusIndicator(presentation: presentation)
            Text(presentation.title)
                .fontWeight(.semibold)
                .foregroundStyle(presentation.color)
        }
        .help(presentation.help)

        if presentation != .loading, presentation != .error {
            if let status {
                if case let .running(pid) = status.runtime {
                    let pidValue = String(pid)
                    HStack(spacing: 5) {
                        Text("\(L10n.Services.pid) \(pidValue)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        copyButton(item: "PID", value: pidValue)
                    }
                }
                let exitStatus = status.lastExitStatus.map(String.init) ?? L10n.Services.unknown
                Text("\(L10n.Services.lastExitStatus): \(exitStatus)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var statusActions: some View {
        ServiceActionsView(store: store, service: service)
            .fixedSize()
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
