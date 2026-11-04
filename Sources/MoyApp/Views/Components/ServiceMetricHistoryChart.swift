import Charts
import SwiftUI

struct ServiceMetricHistoryChart: View {
    let data: ServiceMetricChartData
    let color: Color

    var body: some View {
        Chart {
            ForEach(data.points) { point in
                LineMark(
                    x: .value("timestamp", point.timestamp),
                    y: .value("value", point.value),
                    series: .value("segment", point.segment),
                )
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.linear)
                .foregroundStyle(color)
            }
        }
        .chartXScale(domain: data.timeDomain, range: .plotDimension(padding: 0))
        .chartYScale(domain: data.valueDomain)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .padding(.vertical, 4)
        .frame(height: 44)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
        // 現在値と直近の範囲は親のアクセシビリティ値で伝えます。
        .accessibilityHidden(true)
    }
}

struct ServiceMetricChartData {
    enum Metric {
        case cpu
        case memory
    }

    struct Point: Identifiable {
        let timestamp: Date
        let value: Double
        let segment: Int
        var id: Date {
            timestamp
        }
    }

    let points: [Point]
    let timeDomain: ClosedRange<Date>
    let valueDomain: ClosedRange<Double>

    init(history: ServicesMetricsHistory, metric: Metric) {
        // 空のグラフでも現在時刻を取得せず、計測イベントだけで描画を更新します。
        let end = history.entries.last?.timestamp ?? Date(timeIntervalSince1970: 0)
        timeDomain = end.addingTimeInterval(-ServicesMetricsHistory.duration) ... end
        var points: [Point] = []
        var segment = 0
        var previous: Date?
        for entry in history.entries {
            let value: Double? = switch metric {
            case .cpu: entry.cpuPercent
            case .memory: entry.memoryBytes.map { Double($0) }
            }
            guard let value else {
                segment += 1
                previous = nil
                continue
            }
            if let previous, entry.timestamp.timeIntervalSince(previous) > 5 {
                segment += 1
            }
            points.append(Point(timestamp: entry.timestamp, value: value, segment: segment))
            previous = entry.timestamp
        }
        self.points = points
        let minimum = points.map(\.value).min() ?? 0
        let maximum = points.map(\.value).max() ?? 0
        switch metric {
        case .cpu:
            valueDomain = 0 ... max(100, (maximum / 100).rounded(.up) * 100)
        case .memory:
            // 搭載容量は数値の分母で伝え、グラフは小さな増減も見えるよう範囲を拡大します。
            let padding = max((maximum - minimum) * 0.2, maximum * 0.02, 1_048_576)
            valueDomain = max(0, minimum - padding) ... (maximum + padding)
        }
    }
}
