import Darwin
import Foundation

struct ProcessReading: Sendable {
    let identity: ProcessIdentity
    let timestamp: Date
    /// CPU時間と同じMach absolute timeの単位です。
    let clockTicks: UInt64
    let cpuTicks: MetricValue<UInt64>
    let memoryBytes: MetricValue<UInt64>
}

enum ProcessReadError: Error, Sendable {
    case exited
    case pidReused
    case unavailable(MetricsFailure)
}

protocol ProcessMetricsReading: Sendable {
    func identity(for pid: Int32) throws(ProcessReadError) -> ProcessIdentity
    func read(pid: Int32, metrics: ProcessMetrics) throws(ProcessReadError) -> ProcessReading
}

struct SystemProcessMetricsReader: ProcessMetricsReading {
    func identity(for pid: Int32) throws(ProcessReadError) -> ProcessIdentity {
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        errno = 0
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expectedSize)
        guard size == expectedSize else {
            throw readError(operation: "proc_pidinfo", code: errno == 0 ? EIO : errno)
        }
        // 終了済みの子プロセスが親による回収を待っている場合も終了として扱います。
        guard info.pbi_status != SZOMB else { throw .exited }
        return ProcessIdentity(
            pid: pid,
            startTimeSeconds: info.pbi_start_tvsec,
            startTimeMicroseconds: info.pbi_start_tvusec,
        )
    }

    func read(pid: Int32, metrics: ProcessMetrics) throws(ProcessReadError) -> ProcessReading {
        let before = try identity(for: pid)
        var cpu: MetricValue<UInt64> = .notRequested
        var memory: MetricValue<UInt64> = .notRequested
        if !metrics.isDisjoint(with: [.cpu, .memory]) {
            var usage = rusage_info_v0()
            errno = 0
            let result = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V0, $0)
                }
            }
            if result == 0 {
                if metrics.contains(.cpu) {
                    let total = usage.ri_user_time.addingReportingOverflow(usage.ri_system_time)
                    cpu = total.overflow ? .failed(.counterOverflow) : .value(total.partialValue)
                }
                if metrics.contains(.memory) {
                    memory = .value(usage.ri_phys_footprint)
                }
            } else {
                let failure = readError(operation: "proc_pid_rusage", code: errno)
                switch failure {
                case .exited, .pidReused: throw failure
                case let .unavailable(error):
                    if metrics.contains(.cpu) {
                        cpu = .failed(error)
                    }
                    if metrics.contains(.memory) {
                        memory = .failed(error)
                    }
                }
            }
        }
        let ticks = mach_absolute_time()
        // 取得の途中でPIDが再利用された場合、別プロセスの値を返しません。
        guard try identity(for: pid) == before else { throw .pidReused }
        return ProcessReading(
            identity: before, timestamp: Date(), clockTicks: ticks,
            cpuTicks: cpu, memoryBytes: memory,
        )
    }

    private func readError(operation: String, code: Int32) -> ProcessReadError {
        if code == ESRCH || code == ENOENT {
            return .exited
        }
        return .unavailable(.systemCall(operation: operation, code: code == 0 ? EIO : code))
    }
}
