import Darwin
import Foundation
@testable import MoyApp
import MoyMetrics
import Testing

@Suite("Live service metrics", .timeLimit(.minutes(1)))
struct ServicesMetricsClientTests {
    @Test
    func `live adapter yields physical footprint then CPU samples and can be cancelled`() async {
        let stream = ServicesMetricsClient.live.events(getpid())
        let consumer = Task {
            var iterator = stream.makeAsyncIterator()
            guard case let .capacity(totalMemory) = await iterator.next() else {
                Issue.record("Expected installed memory capacity")
                return
            }
            #expect(totalMemory > 0)
            guard case let .sample(first) = await iterator.next() else {
                Issue.record("Expected initial metrics")
                return
            }
            #expect(first.pid == getpid())
            #expect(first.cpuPercent == .waiting)
            guard case let .value(bytes) = first.memoryBytes else {
                Issue.record("Expected footprint")
                return
            }
            #expect(bytes > 0)
            guard case let .sample(second) = await iterator.next(), case .value = second.cpuPercent else {
                Issue.record("Expected periodic CPU measurement")
                return
            }
            withUnsafeCurrentTask { $0?.cancel() }
            while await iterator.next() != nil {}
        }
        await consumer.value
    }

    @Test
    func `subscribers to the same PID receive the same collected samples`() async {
        let client = ServicesMetricsClient.live
        let first = client.events(getpid())
        let second = client.events(getpid())
        async let firstTimes = sampleTimes(first)
        async let secondTimes = sampleTimes(second)
        let times = await (firstTimes, secondTimes)
        #expect(times.0.count == 2)
        #expect(times.1.count == 2)
        #expect(!Set(times.0).isDisjoint(with: times.1))
    }

    @Test
    func `rapid cancellation does not stop a later subscription`() async {
        let client = ServicesMetricsClient.live
        for _ in 0 ..< 10 {
            let stream = client.events(getpid())
            let task = Task { for await _ in stream {} }
            task.cancel()
            await task.value
        }
        let times = await sampleTimes(client.events(getpid()))
        #expect(times.count == 2)
    }

    private func sampleTimes(_ stream: AsyncStream<ServicesMetricsEvent>) async -> [Date] {
        let consumer = Task {
            var dates: [Date] = []
            for await event in stream {
                if case let .sample(sample) = event {
                    dates.append(sample.timestamp)
                    if dates.count == 2 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
            }
            return dates
        }
        return await consumer.value
    }

    @Test
    func `adding and removing another PID preserves the original CPU baseline`() async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try child.run()
        defer {
            if child.isRunning {
                child.terminate()
            }
            child.waitUntilExit()
        }
        let client = ServicesMetricsClient.live
        let consumer = Task {
            var iterator = client.events(getpid()).makeAsyncIterator()
            _ = await iterator.next() // 搭載容量
            guard case let .sample(first) = await iterator.next() else {
                Issue.record("Expected initial sample")
                return
            }
            #expect(first.cpuPercent == .waiting)
            let childSample = await firstSample(client.events(child.processIdentifier))
            #expect(childSample?.pid == child.processIdentifier)
            // 別PIDの追加と解除を挟んでも、自分の計測基準を取り直しません。
            for _ in 0 ..< 2 {
                guard case let .sample(sample) = await iterator.next(), case .value = sample.cpuPercent else {
                    Issue.record("CPU baseline was reset")
                    break
                }
            }
            withUnsafeCurrentTask { $0?.cancel() }
            while await iterator.next() != nil {}
        }
        await consumer.value
    }

    private func firstSample(_ stream: AsyncStream<ServicesMetricsEvent>) async -> ProcessSample? {
        let consumer = Task {
            var sample: ProcessSample?
            for await event in stream {
                if case let .sample(value) = event {
                    sample = value
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            return sample
        }
        return await consumer.value
    }

    @Test
    func `live status refresh starts immediately and supports cancellation`() async {
        let stream = ServicesMetricsClient.live.refreshTicks()
        let consumer = Task {
            var iterator = stream.makeAsyncIterator()
            #expect(await iterator.next() != nil)
            withUnsafeCurrentTask { $0?.cancel() }
            while await iterator.next() != nil {}
        }
        await consumer.value
    }
}
