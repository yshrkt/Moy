/// 計測する項目。選択されていない項目のOSカウンターは取得しません。
public struct ProcessMetrics: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let cpu = Self(rawValue: 1 << 0)
    public static let memory = Self(rawValue: 1 << 1)
    public static let gpu = Self(rawValue: 1 << 2)
    public static let all: Self = [.cpu, .memory, .gpu]
}

/// OS由来の失敗はerrnoを保持し、表示文言は呼び出し側で決めます。
public enum MetricsFailure: Error, Sendable, Equatable {
    case systemCall(operation: String, code: Int32)
    case counterOverflow
}

public enum MetricValue<Value: Sendable & Equatable>: Sendable, Equatable {
    case notRequested
    case waiting
    case unsupported
    case failed(MetricsFailure)
    case value(Value)
}

public enum ProcessMonitorError: Error, Sendable, Equatable {
    case invalidPID(Int32)
    case invalidInterval
    case unsupportedMetrics
    case finished
    case alreadyConsumed
}
