import Foundation
import MoyMetrics

/// 表示中のセッションだけが保持する、直近60秒・最大31点の計測履歴。
struct ServicesMetricsHistory: Equatable {
    static let duration: TimeInterval = 60
    static let maximumCount = 31

    private(set) var entries: [ServicesMetricsHistoryEntry] = []

    mutating func append(_ sample: ProcessSample) {
        // 壁時計が戻った場合も、時間順の異なるサンプルを線で結ばないよう取り直します。
        if let last = entries.last, sample.timestamp <= last.timestamp {
            entries.removeAll()
        }
        let cutoff = sample.timestamp.addingTimeInterval(-Self.duration)
        entries.removeAll { $0.timestamp < cutoff }
        entries.append(ServicesMetricsHistoryEntry(sample))
        if entries.count > Self.maximumCount {
            entries.removeFirst(entries.count - Self.maximumCount)
        }
    }
}

struct ServicesMetricsHistoryEntry: Equatable, Sendable {
    let timestamp: Date
    let cpuPercent: Double?
    let memoryBytes: UInt64?

    init(_ sample: ProcessSample) {
        timestamp = sample.timestamp
        if case let .value(value) = sample.cpuPercent, value.isFinite, value >= 0 {
            cpuPercent = value
        } else {
            cpuPercent = nil
        }
        if case let .value(value) = sample.memoryBytes {
            memoryBytes = value
        } else {
            memoryBytes = nil
        }
    }
}
