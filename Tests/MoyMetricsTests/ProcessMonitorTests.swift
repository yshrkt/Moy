import Foundation
@testable import MoyMetrics
import Testing

@Suite(.timeLimit(.minutes(1)))
struct ProcessMonitorTests {
    @Test
    func `CPU uses interval deltas and can exceed 100 percent`() async throws {
        let reader = ScriptedMetricsReader([10: [
            reading(clock: 100, cpu: .value(20)),
            reading(clock: 200, cpu: .value(270)),
            reading(clock: 300, cpu: .value(270)),
        ]])
        let monitor = try makeMonitor(reader)
        var iterator = try await monitor.events().makeAsyncIterator()
        let first = try await nextBatch(&iterator)
        #expect(first.samples.first?.cpuPercent == .waiting)
        #expect(first.samples.first?.memoryBytes == .value(4096))
        await monitor.collect()
        #expect(try await nextBatch(&iterator).samples.first?.cpuPercent == .value(250))
        await monitor.collect()
        #expect(try await nextBatch(&iterator).samples.first?.cpuPercent == .value(0))
        await monitor.finish()
        #expect(await iterator.next() == .finished)
        #expect(await iterator.next() == nil)
    }

    @Test
    func `target updates preserve existing baselines and stop removed PID reads`() async throws {
        let reader = ScriptedMetricsReader([
            10: [reading(), reading(clock: 200, cpu: .value(70)), reading(clock: 300, cpu: .value(80))],
            20: [reading(20), reading(20, clock: 200)],
        ])
        let monitor = try makeMonitor(reader)
        var iterator = try await monitor.events().makeAsyncIterator()
        _ = try await nextBatch(&iterator)
        try await monitor.add([10, 20])
        await monitor.collect()
        let second = try await nextBatch(&iterator)
        #expect(second.samples.map(\.pid) == [10, 20])
        #expect(second.samples[0].cpuPercent == .value(50))
        #expect(second.samples[1].cpuPercent == .waiting)
        try await monitor.setPIDs([10])
        let removed = await iterator.next()
        guard case .processEnded(pid: 20, identity: _, reason: .removed) = removed else {
            Issue.record("Expected removal event")
            await monitor.finish()
            return
        }
        await monitor.collect()
        #expect(try await nextBatch(&iterator).samples.first?.cpuPercent == .value(10))
        #expect(reader.state.withLock { $0.readings[20]?.count } == 1)
        await monitor.finish()
    }

    @Test
    func `PID reuse ends only that target and never emits its new process values`() async throws {
        let reader = ScriptedMetricsReader([
            10: [reading(), reading(start: 2, memory: .value(9999))],
            20: [reading(20), reading(20, clock: 200)],
        ])
        let monitor = try makeMonitor(reader, pids: [10, 20])
        var iterator = try await monitor.events().makeAsyncIterator()
        _ = try await nextBatch(&iterator)
        await monitor.collect()
        let ended = await iterator.next()
        guard case let .processEnded(pid, identity, reason) = ended else {
            Issue.record("Expected processEnded")
            await monitor.finish()
            return
        }
        #expect(pid == 10)
        #expect(identity?.startTimeSeconds == 1)
        #expect(reason == .pidReused)
        #expect(try await nextBatch(&iterator).samples.map(\.pid) == [20])
        await monitor.finish()
    }

    @Test
    func `empty monitor remains open and accepts a new PID`() async throws {
        let reader = ScriptedMetricsReader([10: [reading()]])
        let monitor = try makeMonitor(reader, pids: [])
        var iterator = try await monitor.events().makeAsyncIterator()
        await monitor.collect()
        #expect(reader.state.withLock { $0.requests.isEmpty })
        try await monitor.add([10])
        await monitor.collect()
        #expect(try await nextBatch(&iterator).samples.first?.pid == 10)
        await monitor.collect()
        guard case .processEnded(pid: 10, identity: _, reason: .exited) = await iterator.next() else {
            Issue.record("Expected exit")
            await monitor.finish()
            return
        }
        _ = try await nextBatch(&iterator)
        // 全対象終了後も明示的に追加すれば新しいプロセスを監視できます。
        reader.state.withLock {
            $0.readings[10] = [reading(start: 2)]
            $0.identities[10] = reading(start: 2).map(\.identity)
        }
        try await monitor.add([10])
        await monitor.collect()
        #expect(try await nextBatch(&iterator).samples.first?.identity?.startTimeSeconds == 2)
        await monitor.finish()
    }

    @Test
    func `failure and counter reset discard CPU baselines without losing memory`() async throws {
        let failure = MetricsFailure.systemCall(operation: "test", code: 1)
        let reader = ScriptedMetricsReader([10: [
            reading(), reading(clock: 200, cpu: .failed(failure)),
            reading(clock: 300, cpu: .value(60)), reading(clock: 400, cpu: .value(10)),
            reading(clock: 500, cpu: .value(110)),
        ]])
        let monitor = try makeMonitor(reader)
        var iterator = try await monitor.events().makeAsyncIterator()
        _ = try await nextBatch(&iterator)
        await monitor.collect()
        let failed = try await nextBatch(&iterator)
        #expect(failed.samples.first?.cpuPercent == .failed(failure))
        #expect(failed.samples.first?.memoryBytes == .value(4096))
        for _ in 0 ..< 2 {
            await monitor.collect()
            #expect(try await nextBatch(&iterator).samples.first?.cpuPercent == .waiting)
        }
        await monitor.collect()
        #expect(try await nextBatch(&iterator).samples.first?.cpuPercent == .value(100))
        await monitor.finish()
    }

    @Test
    func `identity permission failures are recoverable and are not reported as exits`() async throws {
        let failure = MetricsFailure.systemCall(operation: "test", code: 1)
        let reader = ScriptedMetricsReader([10: [reading(), .failure(.unavailable(failure)), reading(clock: 300)]])
        let monitor = try makeMonitor(reader)
        var iterator = try await monitor.events().makeAsyncIterator()
        _ = try await nextBatch(&iterator)
        await monitor.collect()
        #expect(try await nextBatch(&iterator).samples.first?.memoryBytes == .failed(failure))
        await monitor.collect()
        #expect(try await nextBatch(&iterator).samples.first?.cpuPercent == .waiting)
        await monitor.finish()
    }

    @Test
    func `missing initial PID is not attached to a process created before first sample`() async throws {
        let reader = ScriptedMetricsReader([10: [reading()]])
        reader.state.withLock { $0.identities[10] = .failure(.exited) }
        let monitor = try makeMonitor(reader)
        var iterator = try await monitor.events().makeAsyncIterator()
        guard case .processEnded(pid: 10, identity: nil, reason: .exited) = await iterator.next() else {
            Issue.record("Expected initial exit")
            await monitor.finish()
            return
        }
        #expect(reader.state.withLock { $0.requests.isEmpty })
        await monitor.finish()
    }

    @Test
    func `configuration errors do not partially change target sets`() async throws {
        #expect(throws: ProcessMonitorError.invalidPID(0)) { try ProcessMonitor(pids: [0]) }
        #expect(throws: ProcessMonitorError.invalidInterval) { try ProcessMonitor(interval: .zero) }
        #expect(throws: ProcessMonitorError.invalidInterval) { try ProcessMonitor(interval: .seconds(-1)) }
        #expect(throws: ProcessMonitorError.unsupportedMetrics) {
            try ProcessMonitor(metrics: .init(rawValue: 128))
        }
        let reader = ScriptedMetricsReader([10: [reading(), reading(clock: 200)]])
        let monitor = try makeMonitor(reader)
        var iterator = try await monitor.events().makeAsyncIterator()
        _ = try await nextBatch(&iterator)
        await #expect(throws: ProcessMonitorError.alreadyConsumed) { try await monitor.events() }
        await #expect(throws: ProcessMonitorError.invalidPID(-1)) { try await monitor.setPIDs([-1, 20]) }
        await monitor.collect()
        #expect(try await nextBatch(&iterator).samples.map(\.pid) == [10])
        await monitor.finish()
        await #expect(throws: ProcessMonitorError.finished) { try await monitor.add([20]) }
    }

    private func makeMonitor(
        _ reader: ScriptedMetricsReader, pids: Set<Int32> = [10],
    ) throws -> ProcessMonitor {
        try ProcessMonitor(pids: pids, metrics: .all, interval: .seconds(3600), reader: reader)
    }

    private func nextBatch(
        _ iterator: inout AsyncStream<ProcessMonitorEvent>.Iterator,
    ) async throws -> ProcessSampleBatch {
        let event = try #require(await iterator.next())
        guard case let .samples(batch) = event else {
            throw UnexpectedEvent()
        }
        return batch
    }

    private struct UnexpectedEvent: Error {}
}
