import Foundation

/// PID再利用を区別するため、OSが報告した開始時刻を整数のまま保持します。
public struct ProcessIdentity: Sendable, Equatable, Hashable {
    public let pid: Int32
    public let startTimeSeconds: UInt64
    public let startTimeMicroseconds: UInt64

    public init(pid: Int32, startTimeSeconds: UInt64, startTimeMicroseconds: UInt64) {
        self.pid = pid
        self.startTimeSeconds = startTimeSeconds
        self.startTimeMicroseconds = startTimeMicroseconds
    }
}

public struct ProcessSample: Sendable, Equatable {
    public let pid: Int32
    /// 識別情報の取得にも失敗した場合はnilです。
    public let identity: ProcessIdentity?
    public let timestamp: Date
    /// 1コアを使い切ると100。複数コアを使う場合は100を超えます。
    public let cpuPercent: MetricValue<Double>
    /// physical footprintのバイト数。RSSへのフォールバックは行いません。
    public let memoryBytes: MetricValue<UInt64>
    /// 初回の実装では、指定された場合もunsupportedになります。
    public let gpuPercent: MetricValue<Double>

    public init(
        pid: Int32, identity: ProcessIdentity?, timestamp: Date,
        cpuPercent: MetricValue<Double>, memoryBytes: MetricValue<UInt64>, gpuPercent: MetricValue<Double>,
    ) {
        self.pid = pid
        self.identity = identity
        self.timestamp = timestamp
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.gpuPercent = gpuPercent
    }
}

public struct ProcessSampleBatch: Sendable, Equatable {
    public let timestamp: Date
    /// PID昇順。各プロセスの取得時刻は各サンプルに保持します。
    public let samples: [ProcessSample]

    public init(timestamp: Date, samples: [ProcessSample]) {
        self.timestamp = timestamp
        self.samples = samples
    }
}

public enum ProcessEndReason: Sendable, Equatable {
    case exited
    case pidReused
    case removed
}

public enum ProcessMonitorEvent: Sendable, Equatable {
    case samples(ProcessSampleBatch)
    case processEnded(pid: Int32, identity: ProcessIdentity?, reason: ProcessEndReason)
    /// 明示的なfinishによる終了。Taskキャンセル後の受信は保証しません。
    case finished
}
