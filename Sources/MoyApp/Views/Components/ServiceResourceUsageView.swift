import MoyMetrics
import SwiftUI

struct ServiceResourceUsageView: View {
    @Environment(\.locale) private var locale

    let state: ServicesState
    let pid: Int32

    var body: some View {
        let sample = state.metrics.sample.flatMap { $0.pid == pid ? $0 : nil }
        let unavailable = state.metrics.isUnavailable
        let cpuUnavailable = ServiceResourceUsagePresentation.isUnavailable(
            sample?.cpuPercent, unavailable: unavailable,
        )
        let memoryUnavailable = ServiceResourceUsagePresentation.isUnavailable(
            sample?.memoryBytes, unavailable: unavailable,
        )
        let cpuHistory = ServiceMetricChartData(history: state.metrics.history, metric: .cpu)
        let memoryHistory = ServiceMetricChartData(history: state.metrics.history, metric: .memory)
        HStack(alignment: .top, spacing: 24) {
            ServiceResourceMetricView(
                title: L10n.Services.Metrics.cpu,
                value: ServiceResourceUsagePresentation.cpu(
                    sample?.cpuPercent, unavailable: unavailable, locale: locale,
                ),
                help: cpuUnavailable ? L10n.Services.Metrics.unavailable : L10n.Services.Metrics.cpuHelp,
                history: cpuHistory,
                historyDescription: ServiceResourceUsagePresentation.history(cpuHistory, metric: .cpu, locale: locale),
                color: ServiceStatusPresentation.running.color,
            )
            ServiceResourceMetricView(
                title: L10n.Services.Metrics.memory,
                value: ServiceResourceUsagePresentation.memory(
                    sample?.memoryBytes, totalMemory: state.metrics.physicalMemory,
                    unavailable: unavailable, locale: locale,
                ),
                help: memoryUnavailable ? L10n.Services.Metrics.unavailable : L10n.Services.Metrics.memoryHelp,
                history: memoryHistory,
                historyDescription: ServiceResourceUsagePresentation.history(
                    memoryHistory, metric: .memory, locale: locale,
                ),
                color: ServiceStatusPresentation.running.color,
            )
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ServiceResourceMetricView: View {
    let title: String
    let value: String
    let help: String
    let history: ServiceMetricChartData
    let historyDescription: String?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(title) {
                Text(value)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            ServiceMetricHistoryChart(data: history, color: color)
        }
        .frame(maxWidth: .infinity)
        .help(historyDescription.map { "\(help)\n\($0)" } ?? help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let current = value == "—" ? L10n.Services.Metrics.unavailable : value
        return historyDescription.map { "\(current), \($0)" } ?? current
    }
}

enum ServiceResourceUsagePresentation {
    static func isUnavailable(_ value: MetricValue<some Sendable & Equatable>?, unavailable: Bool) -> Bool {
        if unavailable {
            return true
        }
        switch value {
        case .failed, .unsupported, .notRequested: return true
        case .value, .waiting, nil: return false
        }
    }

    static func cpu(_ value: MetricValue<Double>?, unavailable: Bool, locale: Locale) -> String {
        if unavailable {
            return "—"
        }
        switch value {
        case let .value(percent):
            return (percent / 100).formatted(.percent.precision(.fractionLength(1)).locale(locale))
        case .waiting, nil: return L10n.Services.Metrics.measuring
        case .failed, .unsupported, .notRequested: return "—"
        }
    }

    static func memory(
        _ value: MetricValue<UInt64>?, totalMemory: UInt64? = nil, unavailable: Bool, locale: Locale,
    ) -> String {
        if unavailable {
            return "—"
        }
        switch value {
        case let .value(bytes):
            let usage = Int64(clamping: bytes).formatted(.byteCount(style: .memory).locale(locale))
            guard let totalMemory, totalMemory > 0 else { return usage }
            let capacity = Int64(clamping: totalMemory).formatted(.byteCount(style: .memory).locale(locale))
            return L10n.Services.Metrics.memoryUsage(usage, capacity)
        case .waiting, nil: return L10n.Services.Metrics.measuring
        case .failed, .unsupported, .notRequested: return "—"
        }
    }

    static func history(
        _ data: ServiceMetricChartData, metric: ServiceMetricChartData.Metric, locale: Locale,
    ) -> String? {
        guard let minimum = data.points.map(\.value).min(), let maximum = data.points.map(\.value).max() else {
            return nil
        }
        let format: (Double) -> String = { value in
            switch metric {
            case .cpu: return cpu(.value(value), unavailable: false, locale: locale)
            case .memory:
                let bytes = value >= Double(UInt64.max) ? UInt64.max : UInt64(value)
                return memory(.value(bytes), unavailable: false, locale: locale)
            }
        }
        return L10n.Services.Metrics.historyRange(format(minimum), format(maximum))
    }
}
