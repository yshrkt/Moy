import Foundation
@testable import MoyMetrics
import Synchronization

final class ScriptedMetricsReader: ProcessMetricsReading, Sendable {
    struct State {
        var readings: [Int32: [Result<ProcessReading, ProcessReadError>]] = [:]
        var identities: [Int32: Result<ProcessIdentity, ProcessReadError>] = [:]
        var requests: [ProcessMetrics] = []
    }

    let state: Mutex<State>

    init(_ readings: [Int32: [Result<ProcessReading, ProcessReadError>]]) {
        var initial = State(readings: readings)
        for (pid, results) in readings {
            initial.identities[pid] = results.first.map { $0.map(\.identity) }
        }
        state = Mutex(initial)
    }

    func identity(for pid: Int32) throws(ProcessReadError) -> ProcessIdentity {
        let result = state.withLock { $0.identities[pid] ?? .failure(.exited) }
        switch result {
        case let .success(identity): return identity
        case let .failure(error): throw error
        }
    }

    func read(pid: Int32, metrics: ProcessMetrics) throws(ProcessReadError) -> ProcessReading {
        let result: Result<ProcessReading, ProcessReadError> = state.withLock { state in
            state.requests.append(metrics)
            guard var values = state.readings[pid], !values.isEmpty else { return .failure(.exited) }
            let value = values.removeFirst()
            state.readings[pid] = values
            return value
        }
        switch result {
        case let .success(value): return value
        case let .failure(error): throw error
        }
    }
}

func reading(
    _ pid: Int32 = 10, start: UInt64 = 1, clock: UInt64 = 100,
    cpu: MetricValue<UInt64> = .value(20), memory: MetricValue<UInt64> = .value(4096),
) -> Result<ProcessReading, ProcessReadError> {
    .success(ProcessReading(
        identity: ProcessIdentity(pid: pid, startTimeSeconds: start, startTimeMicroseconds: 123),
        timestamp: Date(timeIntervalSince1970: Double(clock)),
        clockTicks: clock, cpuTicks: cpu, memoryBytes: memory,
    ))
}
