import Foundation

/// 複数PIDを1つのループで計測する、単一購読者向けの監視セッションです。
public actor ProcessMonitor {
    struct Target {
        var identity: ProcessIdentity?
        var baseline: ProcessReading?
        var initialError: ProcessReadError?
    }

    private let metrics: ProcessMetrics
    private let interval: Duration
    private let reader: any ProcessMetricsReading
    private let stream: AsyncStream<ProcessMonitorEvent>
    private let continuation: AsyncStream<ProcessMonitorEvent>.Continuation
    private var targets: [Int32: Target] = [:]
    private var worker: Task<Void, Never>?
    private var hasConsumer = false
    private var isFinished = false

    public init(
        pids: Set<Int32> = [],
        metrics: ProcessMetrics = [.cpu, .memory],
        interval: Duration = .seconds(2),
    ) throws {
        try Self.validate(pids: pids, metrics: metrics, interval: interval)
        self.metrics = metrics
        self.interval = interval
        reader = SystemProcessMetricsReader()
        (stream, continuation) = AsyncStream.makeStream()
        targets = Self.makeTargets(pids, reader: reader)
    }

    init(
        pids: Set<Int32>, metrics: ProcessMetrics, interval: Duration,
        reader: any ProcessMetricsReading,
    ) throws {
        try Self.validate(pids: pids, metrics: metrics, interval: interval)
        self.metrics = metrics
        self.interval = interval
        self.reader = reader
        (stream, continuation) = AsyncStream.makeStream()
        targets = Self.makeTargets(pids, reader: reader)
    }

    deinit {
        worker?.cancel()
        continuation.finish()
    }

    /// 初回の呼び出しで計測を開始します。2回目以降はalreadyConsumedを返します。
    /// イベントは順序を保って蓄積するため、呼び出し側は継続的に消費してください。
    /// ループをbreakする場合はfinishも呼び出してください。
    public func events() throws -> AsyncStream<ProcessMonitorEvent> {
        guard !isFinished else { throw ProcessMonitorError.finished }
        guard !hasConsumer else { throw ProcessMonitorError.alreadyConsumed }
        hasConsumer = true
        continuation.onTermination = { [weak self] _ in
            Task { await self?.cancel() }
        }
        collect()
        let interval = interval
        worker = Task.detached { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                guard await self?.collect() == true else { return }
            }
        }
        return stream
    }

    public func add(_ pids: Set<Int32>) throws {
        guard !isFinished else { throw ProcessMonitorError.finished }
        try Self.validate(pids: pids, metrics: metrics, interval: interval)
        for pid in pids.sorted() where targets[pid] == nil {
            targets[pid] = Self.makeTarget(pid, reader: reader)
        }
    }

    public func remove(_ pids: Set<Int32>) {
        guard !isFinished else { return }
        for pid in pids.sorted() {
            end(pid: pid, reason: .removed)
        }
    }

    /// 継続するPIDの識別情報とCPU基準値を維持したまま対象を置き換えます。
    public func setPIDs(_ pids: Set<Int32>) throws {
        guard !isFinished else { throw ProcessMonitorError.finished }
        try Self.validate(pids: pids, metrics: metrics, interval: interval)
        remove(Set(targets.keys).subtracting(pids))
        try add(pids)
    }

    public func finish() {
        guard !isFinished else { return }
        continuation.yield(.finished)
        cancel()
    }

    private func cancel() {
        isFinished = true
        worker?.cancel()
        worker = nil
        targets.removeAll()
        continuation.finish()
    }

    private static func validate(pids: Set<Int32>, metrics: ProcessMetrics, interval: Duration) throws {
        if let pid = pids.sorted().first(where: { $0 <= 0 }) {
            throw ProcessMonitorError.invalidPID(pid)
        }
        guard interval > .zero else { throw ProcessMonitorError.invalidInterval }
        guard metrics.subtracting(.all).isEmpty else { throw ProcessMonitorError.unsupportedMetrics }
    }

    private static func makeTargets(
        _ pids: Set<Int32>, reader: any ProcessMetricsReading,
    ) -> [Int32: Target] {
        Dictionary(uniqueKeysWithValues: pids.map { ($0, makeTarget($0, reader: reader)) })
    }

    private static func makeTarget(_ pid: Int32, reader: any ProcessMetricsReading) -> Target {
        do {
            return try Target(identity: reader.identity(for: pid))
        } catch {
            return Target(initialError: error)
        }
    }
}

extension ProcessMonitor {
    @discardableResult
    func collect() -> Bool {
        guard !isFinished, !Task.isCancelled else { return false }
        // 対象が空でもStreamを維持しますが、空のサンプルやOSへの問い合わせは発生させません。
        guard !targets.isEmpty else { return true }
        let timestamp = Date()
        var samples: [ProcessSample] = []
        for pid in targets.keys.sorted() {
            guard var target = targets[pid] else { continue }
            do {
                let reading = try read(pid: pid, target: &target)
                if let identity = target.identity, identity != reading.identity {
                    end(pid: pid, reason: .pidReused)
                    continue
                }
                target.identity = reading.identity
                samples.append(ProcessSample(
                    pid: pid, identity: reading.identity, timestamp: reading.timestamp,
                    cpuPercent: cpuPercent(reading, baseline: target.baseline),
                    memoryBytes: reading.memoryBytes,
                    gpuPercent: metrics.contains(.gpu) ? .unsupported : .notRequested,
                ))
                if case .value = reading.cpuTicks {
                    target.baseline = reading
                } else {
                    target.baseline = nil
                }
                targets[pid] = target
            } catch {
                switch error {
                case .exited: end(pid: pid, reason: .exited)
                case .pidReused: end(pid: pid, reason: .pidReused)
                case let .unavailable(failure):
                    target.baseline = nil
                    targets[pid] = target
                    samples.append(ProcessSample(
                        pid: pid, identity: target.identity, timestamp: Date(),
                        cpuPercent: metrics.contains(.cpu) ? .failed(failure) : .notRequested,
                        memoryBytes: metrics.contains(.memory) ? .failed(failure) : .notRequested,
                        gpuPercent: metrics.contains(.gpu) ? .unsupported : .notRequested,
                    ))
                }
            }
        }
        continuation.yield(.samples(ProcessSampleBatch(timestamp: timestamp, samples: samples)))
        return true
    }

    private func cpuPercent(_ reading: ProcessReading, baseline: ProcessReading?) -> MetricValue<Double> {
        switch reading.cpuTicks {
        case .notRequested: return .notRequested
        case .waiting: return .waiting
        case .unsupported: return .unsupported
        case let .failed(error): return .failed(error)
        case let .value(current):
            guard let baseline, case let .value(previous) = baseline.cpuTicks,
                  current >= previous, reading.clockTicks > baseline.clockTicks
            else { return .waiting }
            // 両カウンターがMach absolute timeなので、timebaseの変換係数は相殺されます。
            let cpu = Double(current - previous)
            let elapsed = Double(reading.clockTicks - baseline.clockTicks)
            return .value(cpu / elapsed * 100)
        }
    }

    private func read(pid: Int32, target: inout Target) throws(ProcessReadError) -> ProcessReading {
        if let error = target.initialError {
            target.initialError = nil
            throw error
        }
        return try reader.read(pid: pid, metrics: metrics)
    }

    func end(pid: Int32, reason: ProcessEndReason) {
        guard let target = targets.removeValue(forKey: pid) else { return }
        continuation.yield(.processEnded(pid: pid, identity: target.identity, reason: reason))
    }
}
