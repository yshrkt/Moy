import Darwin
@testable import MoyApp
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
