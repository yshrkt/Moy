import MoyKit
import NanoRedux
import SwiftUI

@MainActor
struct ServiceDetailView: View {
    let store: ServicesStore
    let service: ServiceDefinition

    var body: some View {
        ScrollView {
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
            .frame(maxWidth: 760, alignment: .leading)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.send(.presentEditService(service.identifier))
                } label: {
                    Label(L10n.Common.edit, systemImage: "pencil")
                }
                Button(role: .destructive) {
                    store.send(.requestDeleteService(service.identifier))
                } label: {
                    Label(L10n.Common.delete, systemImage: "trash")
                }
                .disabled(store.state.isOperating(service.identifier))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(service.name)
                    .font(.largeTitle.bold())
                if let description = service.description, !description.isEmpty {
                    Text(description)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            ServiceActionsView(store: store, service: service)
        }
    }

    private var statusSection: some View {
        DetailSection(title: L10n.Services.status) {
            let status = store.state.statuses[service.identifier]
            LabeledContent(L10n.Services.status) {
                ServiceStatusView(
                    status: status,
                    statusUnavailable: store.state.statusFailures.contains(service.identifier),
                )
            }
            if let status {
                if case let .running(pid) = status.runtime {
                    LabeledContent(L10n.Services.pid, value: String(pid))
                }
                LabeledContent(
                    L10n.Services.lastExitStatus,
                    value: status.lastExitStatus.map(String.init) ?? L10n.Services.unknown,
                )
            }
        }
    }

    private var identitySection: some View {
        DetailSection(title: L10n.Services.identity) {
            LabeledContent(L10n.Services.identifier) {
                CopyableValue(service.identifier.rawValue)
            }
            LabeledContent(L10n.Services.label) {
                CopyableValue(service.identifier.launchdLabel)
            }
        }
    }

    private var configurationSection: some View {
        DetailSection(title: L10n.Services.configuration) {
            LabeledContent(L10n.Services.executable) {
                CopyableValue(service.programArguments.first ?? "")
            }
            if service.programArguments.count > 1 {
                LabeledContent(L10n.Services.arguments) {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(Array(service.programArguments.dropFirst().enumerated()), id: \.offset) { _, argument in
                            Text(argument.isEmpty ? "\"\"" : argument)
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            if let workingDirectory = service.workingDirectory {
                LabeledContent(L10n.Services.workingDirectory) {
                    CopyableValue(workingDirectory)
                }
            }
            if !service.environmentVariables.isEmpty {
                LabeledContent(L10n.Services.environment) {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(service.environmentVariables.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            Text("\(key)=\(value)")
                                .font(.body.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var behaviorSection: some View {
        DetailSection(title: L10n.Services.behavior) {
            LabeledContent(L10n.Services.runAtLoad, value: booleanText(service.runAtLoad))
            LabeledContent(L10n.Services.keepAlive, value: booleanText(service.keepAlive))
            if let throttleInterval = service.throttleInterval {
                LabeledContent(
                    L10n.Services.throttleInterval,
                    value: "\(throttleInterval) \(L10n.Services.seconds)",
                )
            }
        }
    }

    private var logsSection: some View {
        DetailSection(title: L10n.Services.logs) {
            logRow(title: L10n.Services.standardOut, path: service.standardOutPath)
            logRow(title: L10n.Services.standardError, path: service.standardErrorPath)
        }
    }

    private func logRow(title: String, path: String) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 7) {
                CopyableValue(path)
                HStack {
                    Button(L10n.Common.open) {
                        store.send(.openLog(path))
                    }
                    Button(L10n.Common.reveal) {
                        store.send(.revealLog(path))
                    }
                }
            }
        }
    }

    private func booleanText(_ value: Bool) -> String {
        value ? L10n.Services.enabled : L10n.Services.disabled
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(14)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
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
            .multilineTextAlignment(.trailing)
    }
}
