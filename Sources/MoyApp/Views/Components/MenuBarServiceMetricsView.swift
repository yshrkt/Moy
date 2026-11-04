import SwiftUI

struct MenuBarServiceLabel: View {
    let state: ServicesState
    let name: String
    let pid: Int32?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).lineLimit(1)
            if let pid {
                MenuBarServiceMetricsView(state: state, pid: pid)
            }
        }
    }
}

struct MenuBarServiceMetricsView: View {
    @Environment(\.locale) private var locale

    let state: ServicesState
    let pid: Int32

    var body: some View {
        let process = state.metrics.processes[pid]
        let sample = process?.sample
        let unavailable = process?.isUnavailable ?? false
        let cpu = ServiceResourceUsagePresentation.cpu(sample?.cpuPercent, unavailable: unavailable, locale: locale)
        let memory = ServiceResourceUsagePresentation.memory(
            sample?.memoryBytes, unavailable: unavailable, locale: locale,
        )
        let text = sample == nil && !unavailable ? L10n.Services.Metrics.measuring
            : L10n.Services.Metrics.summary(cpu, memory)
        let cpuFailed = ServiceResourceUsagePresentation.isUnavailable(sample?.cpuPercent, unavailable: unavailable)
        let memoryFailed = ServiceResourceUsagePresentation.isUnavailable(sample?.memoryBytes, unavailable: unavailable)
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .help(cpuFailed || memoryFailed ? L10n.Services.Metrics.unavailable : text)
            .accessibilityLabel(L10n.Services.Metrics.summary(
                cpuFailed ? L10n.Services.Metrics.unavailable : cpu,
                memoryFailed ? L10n.Services.Metrics.unavailable : memory,
            ))
    }
}
