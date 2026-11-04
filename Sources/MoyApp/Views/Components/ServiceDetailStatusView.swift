import MoyKit
import SwiftUI

@MainActor
struct ServiceDetailStatusView: View {
    @Environment(\.colorScheme) private var colorScheme

    let store: ServicesStore
    let service: ServiceDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusSummary
            if statusPresentation == .running,
               let pid = store.state.statuses[service.identifier]?.metricsPID
            {
                Divider()
                ServiceResourceUsageView(state: store.state, pid: pid)
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

    private var statusSummary: some View {
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
                        CopyValueButton(store: store, identifier: service.identifier, item: "PID", value: pidValue)
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
}
