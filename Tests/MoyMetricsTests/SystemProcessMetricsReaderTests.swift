import Darwin
import Foundation
@testable import MoyMetrics
import Testing

@Suite(.timeLimit(.minutes(1)))
struct SystemProcessMetricsReaderTests {
    @Test
    func `live reader returns own identity and physical footprint`() throws {
        let reader = SystemProcessMetricsReader()
        let identity = try reader.identity(for: getpid())
        let sample = try reader.read(pid: getpid(), metrics: [.cpu, .memory])
        #expect(sample.identity == identity)
        #expect(identity.pid == getpid())
        #expect(identity.startTimeSeconds > 0)
        guard case let .value(memory) = sample.memoryBytes, case let .value(cpu) = sample.cpuTicks else {
            Issue.record("Expected live memory and CPU counters")
            return
        }
        #expect(memory > 0)
        #expect(cpu > 0)
        #expect(sample.clockTicks > 0)
    }

    @Test
    func `unselected metrics are not exposed and GPU is explicitly unsupported`() async throws {
        let reader = SystemProcessMetricsReader()
        let sample = try reader.read(pid: getpid(), metrics: .gpu)
        #expect(sample.cpuTicks == .notRequested)
        #expect(sample.memoryBytes == .notRequested)
        let monitor = try ProcessMonitor(pids: [getpid()], metrics: .gpu)
        var iterator = try await monitor.events().makeAsyncIterator()
        guard case let .samples(batch) = await iterator.next() else {
            Issue.record("Expected sample")
            await monitor.finish()
            return
        }
        #expect(batch.samples.first?.gpuPercent == .unsupported)
        #expect(batch.samples.first?.cpuPercent == .notRequested)
        #expect(batch.samples.first?.memoryBytes == .notRequested)
        await monitor.finish()
    }

    @Test
    func `memory only selection does not return CPU counters`() throws {
        let sample = try SystemProcessMetricsReader().read(pid: getpid(), metrics: .memory)
        #expect(sample.cpuTicks == .notRequested)
        guard case let .value(memory) = sample.memoryBytes else {
            Issue.record("Expected physical footprint")
            return
        }
        #expect(memory > 0)
    }

    @Test
    func `exited child process produces an exit event`() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
        }
        let monitor = try ProcessMonitor(pids: [process.processIdentifier], interval: .seconds(3600))
        var iterator = try await monitor.events().makeAsyncIterator()
        guard case .samples = await iterator.next() else {
            Issue.record("Expected initial sample")
            await monitor.finish()
            return
        }
        process.terminate()
        process.waitUntilExit()
        await monitor.collect()
        guard case let .processEnded(pid, _, reason) = await iterator.next() else {
            Issue.record("Expected child exit")
            await monitor.finish()
            return
        }
        #expect(pid == process.processIdentifier)
        #expect(reason == .exited)
        await monitor.finish()
    }

    @Test
    func `CPU counters use Mach ticks rather than nanoseconds`() throws {
        let reader = SystemProcessMetricsReader()
        var before = rusage()
        #expect(getrusage(RUSAGE_SELF, &before) == 0)
        let first = try reader.read(pid: getpid(), metrics: .cpu)
        // 単位の取り違え（Apple Siliconでは約24〜42倍）を検出するためCPU時間を積みます。
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(30))
        while ContinuousClock.now < deadline {
            _ = mach_absolute_time()
        }
        let last = try reader.read(pid: getpid(), metrics: .cpu)
        var after = rusage()
        #expect(getrusage(RUSAGE_SELF, &after) == 0)
        guard case let .value(initial) = first.cpuTicks, case let .value(final) = last.cpuTicks else {
            Issue.record("Expected CPU counters")
            return
        }
        var timebase = mach_timebase_info_data_t()
        #expect(mach_timebase_info(&timebase) == KERN_SUCCESS)
        let measured = Double(final - initial) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        let reference = seconds(after.ru_utime) + seconds(after.ru_stime)
            - seconds(before.ru_utime) - seconds(before.ru_stime)
        #expect(measured > 0)
        #expect(measured > reference * 0.5)
        #expect(measured < reference * 1.5)
    }

    @Test
    func `timer emits samples and consumer cancellation finishes the session`() async throws {
        let monitor = try ProcessMonitor(pids: [getpid()], interval: .milliseconds(5))
        let stream = try await monitor.events()
        let consumer = Task {
            var iterator = stream.makeAsyncIterator()
            _ = await iterator.next()
            guard case let .samples(batch) = await iterator.next() else {
                Issue.record("Expected periodic sample")
                return
            }
            guard case .value = batch.samples.first?.cpuPercent else {
                Issue.record("Expected measured CPU")
                return
            }
            withUnsafeCurrentTask { $0?.cancel() }
            while await iterator.next() != nil {}
        }
        await consumer.value
        // onTerminationからactorへの通知が処理されるまで、上限付きで待ちます。
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            if await !(monitor.collect()) {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Cancelled stream kept collecting")
        await monitor.finish()
    }

    @Test
    func `releasing a monitor ends its stream without retaining its timer`() async throws {
        var monitor: ProcessMonitor? = try ProcessMonitor(pids: [], interval: .milliseconds(5))
        weak var reference = monitor
        let stream = try await #require(monitor).events()
        monitor = nil
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == nil)
        #expect(reference == nil)
    }

    private func seconds(_ time: timeval) -> Double {
        Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
    }
}
