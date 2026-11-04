import Foundation
@testable import MoyApp
import MoyKit
import MoyMetrics
import NanoRedux
import Synchronization
import Testing

@MainActor
@Suite("Service detail metrics", .timeLimit(.minutes(1)))
struct ServicesMetricsTests {
    @Test
    func `visible details consume samples once and hiding cancels the subscription`() async throws {
        let fixture = try Fixture()
        let store = fixture.store()
        store.send(.metrics(.setVisibility(fixture.service.identifier, true)))
        try await waitFor { fixture.probe.started == [10] }
        let session = try #require(store.state.metrics.session)
        let sample = makeSample(pid: 10)
        fixture.probe.yield(.sample(sample), pid: 10)
        try await waitFor { store.state.metrics.sample == sample }
        store.send(.metrics(.setVisibility(fixture.service.identifier, true)))
        store.send(.receiveServices(.success(fixture.snapshot(pid: 10))))
        store.send(.metrics(.setVisibility(fixture.service.identifier, false)))
        try await waitFor { fixture.probe.stopped == [10] }
        #expect(fixture.probe.started == [10])
        #expect(store.state.metrics.session == nil)
        #expect(store.state.metrics.sample == nil)
        #expect(store.state.metrics.history.entries.isEmpty)
        store.send(.metrics(.receive(session.id, .sample(sample))))
        // キュー内の古い結果が届いても、次の同期通知まで監視を再開しません。
        store.send(.selectService(nil))
        try await waitFor { store.state.selectedIdentifier == nil }
        #expect(store.state.metrics.sample == nil)
    }

    @Test
    func `selection switch rejects the old window callback and old samples`() async throws {
        let fixture = try Fixture()
        let second = try fixture.makeService("second")
        let store = fixture.store()
        store.state.services.append(second)
        store.state.statuses[second.identifier] = ServiceStatus(
            identifier: second.identifier, registration: .enabled, runtime: .running(pid: 20),
        )
        store.send(.metrics(.setVisibility(fixture.service.identifier, true)))
        try await waitFor { fixture.probe.started == [10] }
        let old = try #require(store.state.metrics.session)
        store.send(.selectService(second.identifier))
        store.send(.metrics(.setVisibility(second.identifier, true)))
        store.send(.metrics(.setVisibility(fixture.service.identifier, false)))
        store.send(.metrics(.receive(old.id, .sample(makeSample(pid: 10)))))
        try await waitFor { fixture.probe.started == [10, 20] && fixture.probe.stopped == [10] }
        #expect(store.state.metrics.visibleIdentifier == second.identifier)
        #expect(store.state.metrics.sample == nil)
        #expect(store.state.metrics.history.entries.isEmpty)
        let sample = makeSample(pid: 20)
        fixture.probe.yield(.sample(sample), pid: 20)
        try await waitFor { store.state.metrics.sample == sample }
        store.send(.metrics(.setVisibility(second.identifier, false)))
        try await waitFor { fixture.probe.stopped.count == 2 }
    }

    @Test
    func `PID changes replace monitoring and discard old results`() async throws {
        let fixture = try Fixture()
        let store = fixture.store()
        store.send(.metrics(.setVisibility(fixture.service.identifier, true)))
        try await waitFor { fixture.probe.started == [10] }
        let old = try #require(store.state.metrics.session)
        store.send(.receiveServices(.success(fixture.snapshot(pid: 11))))
        store.send(.metrics(.receive(old.id, .sample(makeSample(pid: 10)))))
        try await waitFor { fixture.probe.started == [10, 11] && fixture.probe.stopped == [10] }
        #expect(store.state.metrics.session?.pid == 11)
        #expect(store.state.metrics.sample == nil)
        #expect(store.state.metrics.history.entries.isEmpty)
        fixture.probe.yield(.sample(makeSample(pid: 11)), pid: 11)
        try await waitFor { store.state.metrics.sample?.pid == 11 }
        store.send(.metrics(.setVisibility(fixture.service.identifier, false)))
        try await waitFor { fixture.probe.stopped.count == 2 }
    }

    @Test
    func `waiting disabled and failed status do not retain a metrics subscription`() async throws {
        let fixture = try Fixture()
        let store = fixture.store()
        store.state.statuses[fixture.service.identifier] = ServiceStatus(
            identifier: fixture.service.identifier, registration: .enabled, runtime: .waiting,
        )
        store.send(.metrics(.setVisibility(fixture.service.identifier, true)))
        try await waitFor { store.state.metrics.visibleIdentifier != nil }
        #expect(fixture.probe.started.isEmpty)
        store.send(.receiveServices(.success(fixture.snapshot(pid: 10))))
        try await waitFor { fixture.probe.started == [10] }
        store.send(.receiveServices(.success(.init(
            services: [fixture.service], statuses: [:], statusFailures: [fixture.service.identifier],
        ))))
        try await waitFor { fixture.probe.stopped == [10] }
        #expect(store.state.metrics.sample == nil)
        store.send(.receiveServices(.success(fixture.snapshot(pid: 10, registration: .disabled))))
        store.send(.metrics(.setVisibility(fixture.service.identifier, false)))
        try await waitFor { store.state.metrics.visibleIdentifier == nil }
        #expect(fixture.probe.started == [10])
    }

    @Test
    func `restart clears the current sample until refreshed status is received`() throws {
        let fixture = try Fixture()
        let reducer = fixture.reducer()
        var state = fixture.state()
        _ = reducer.reduce(into: &state, action: .metrics(.setVisibility(fixture.service.identifier, true)))
        let session = try #require(state.metrics.session)
        _ = reducer.reduce(into: &state, action: .metrics(.receive(session.id, .sample(makeSample(pid: 10)))))
        #expect(state.metrics.sample != nil)
        #expect(state.metrics.history.entries.count == 1)
        _ = reducer.reduce(into: &state, action: .operation(.restart(fixture.service.identifier)))
        #expect(state.metrics.session == nil)
        #expect(state.metrics.sample == nil)
        #expect(state.metrics.history.entries.isEmpty)
        _ = reducer.reduce(into: &state, action: .operation(.receive(fixture.service.identifier, .success(()))))
        #expect(state.metrics.session == nil)
        _ = reducer.reduce(into: &state, action: .receiveServices(.success(fixture.snapshot(pid: 11))))
        #expect(state.metrics.session?.pid == 11)
        #expect(state.metrics.session?.id != session.id)
    }

    @Test
    func `ended or failed monitoring clears values without changing service status`() throws {
        let fixture = try Fixture()
        let reducer = fixture.reducer()
        for event in [ServicesMetricsEvent.ended, .failed] {
            var state = fixture.state()
            _ = reducer.reduce(into: &state, action: .metrics(.setVisibility(fixture.service.identifier, true)))
            let session = try #require(state.metrics.session)
            _ = reducer.reduce(into: &state, action: .metrics(.receive(session.id, .sample(makeSample(pid: 10)))))
            _ = reducer.reduce(into: &state, action: .metrics(.receive(session.id, event)))
            #expect(state.metrics.sample == nil)
            #expect(state.metrics.history.entries.isEmpty)
            #expect(state.metrics.isUnavailable)
            #expect(state.statuses[fixture.service.identifier]?.metricsPID == 10)
            #expect(state.failure == nil)
        }
    }

    @Test
    func `detail status polling is subscribed and cancelled with visibility`() async throws {
        let fixture = try Fixture()
        let store = fixture.store()
        store.send(.metrics(.setVisibility(fixture.service.identifier, true)))
        try await waitFor { fixture.probe.refreshStarts == 1 && fixture.probe.started == [10] }
        fixture.probe.tick()
        // テスト用UseCaseはdisabledを返します。状態更新に応じて計測も停止します。
        try await waitFor { fixture.probe.stopped == [10] }
        #expect(store.state.statuses[fixture.service.identifier]?.registration == .disabled)
        store.send(.metrics(.setVisibility(fixture.service.identifier, false)))
        try await waitFor { fixture.probe.refreshStops == 1 }
        #expect(store.state.metrics.session == nil)
    }

    private func waitFor(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(condition())
    }

    @MainActor
    private struct Fixture {
        let service: ServiceDefinition
        let probe = MetricsProbe()

        init() throws {
            service = try ServiceDefinition(
                identifier: ServiceIdentifier("worker"), programArguments: ["/usr/bin/true"],
                standardOutPath: "/tmp/worker.out", standardErrorPath: "/tmp/worker.err",
            )
        }

        func makeService(_ identifier: String) throws -> ServiceDefinition {
            try ServiceDefinition(
                identifier: ServiceIdentifier(identifier), programArguments: ["/usr/bin/true"],
                standardOutPath: "/tmp/worker.out", standardErrorPath: "/tmp/worker.err",
            )
        }

        func state() -> ServicesState {
            let state = ServicesState()
            state.services = [service]
            state.selectedIdentifier = service.identifier
            state.statuses = snapshot(pid: 10).statuses
            return state
        }

        func snapshot(pid: Int32, registration: ServiceStatus.Registration = .enabled) -> ServicesSnapshot {
            .init(services: [service], statuses: [service.identifier: ServiceStatus(
                identifier: service.identifier, registration: registration, runtime: .running(pid: pid),
            )], statusFailures: [])
        }

        func reducer() -> ServicesReducer {
            ServicesReducer(dependencies: .init(
                serviceManagementUseCase: TestServiceManagementUseCase(services: [service]),
                metricsClient: probe.client,
            ))
        }

        func store() -> some Store<ServicesState, ServicesAction> {
            StoreBuilder.reducer(initialState: state(), reducer: reducer())
        }
    }
}

func makeSample(
    pid: Int32, cpu: MetricValue<Double> = .value(12.3),
    memory: MetricValue<UInt64> = .value(128 * 1024 * 1024), timestamp: Date = Date(),
) -> ProcessSample {
    .init(
        pid: pid, identity: .init(pid: pid, startTimeSeconds: 1, startTimeMicroseconds: 0), timestamp: timestamp,
        cpuPercent: cpu, memoryBytes: memory, gpuPercent: .notRequested,
    )
}

final class MetricsProbe: Sendable {
    private struct State {
        var started: [Int32] = []
        var stopped: [Int32] = []
        var continuations: [Int32: AsyncStream<ServicesMetricsEvent>.Continuation] = [:]
        var refreshContinuation: AsyncStream<Void>.Continuation?
        var refreshStarts = 0
        var refreshStops = 0
    }

    private let state = Mutex(State())
    var started: [Int32] {
        state.withLock { $0.started }
    }

    var stopped: [Int32] {
        state.withLock { $0.stopped }
    }

    var refreshStarts: Int {
        state.withLock { $0.refreshStarts }
    }

    var refreshStops: Int {
        state.withLock { $0.refreshStops }
    }

    var client: ServicesMetricsClient {
        .init(events: { [self] pid in
            AsyncStream { continuation in
                state.withLock {
                    $0.started.append(pid)
                    $0.continuations[pid] = continuation
                }
                continuation.onTermination = { [self] _ in
                    state.withLock { $0.stopped.append(pid) }
                }
            }
        }, refreshTicks: { [self] in
            AsyncStream { continuation in
                state.withLock {
                    $0.refreshContinuation = continuation
                    $0.refreshStarts += 1
                }
                continuation.onTermination = { [self] _ in
                    state.withLock { $0.refreshStops += 1 }
                }
            }
        })
    }

    func yield(_ event: ServicesMetricsEvent, pid: Int32) {
        state.withLock { $0.continuations[pid] }?.yield(event)
    }

    func tick() {
        state.withLock { $0.refreshContinuation }?.yield(())
    }
}
