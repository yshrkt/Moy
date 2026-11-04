import Foundation
@testable import MoyApp
import MoyKit
import NanoRedux
import Testing

@MainActor
@Suite("Menu bar metrics", .timeLimit(.minutes(1)))
struct MenuBarMetricsTests {
    @Test
    func `menu subscribes to running services and closing it releases all targets`() async throws {
        let fixture = try Fixture()
        let store = try fixture.store()
        store.send(.metrics(.setMenuVisibility(true)))
        try await waitFor { Set(fixture.probe.started) == [10, 20] }
        fixture.probe.yield(.sample(makeSample(pid: 10)), pid: 10)
        fixture.probe.yield(.sample(makeSample(pid: 20)), pid: 20)
        try await waitFor { store.state.metrics.processes[20]?.sample != nil }
        #expect(store.state.metrics.sample == nil)
        #expect(store.state.metrics.history.entries.isEmpty)
        #expect(store.state.metrics.processes.count == 2)
        store.send(.metrics(.setMenuVisibility(false)))
        try await waitFor { Set(fixture.probe.stopped) == [10, 20] && fixture.probe.refreshStops == 1 }
        #expect(store.state.metrics.processes.isEmpty)
    }

    @Test
    func `opening and closing the menu preserves the visible detail subscription and history`() async throws {
        let fixture = try Fixture()
        let store = try fixture.store()
        store.send(.metrics(.setVisibility(fixture.first.identifier, true)))
        try await waitFor { fixture.probe.started == [10] }
        let sample = makeSample(pid: 10)
        fixture.probe.yield(.sample(sample), pid: 10)
        try await waitFor { store.state.metrics.sample == sample }
        let session = try #require(store.state.metrics.session)
        store.send(.metrics(.setMenuVisibility(true)))
        try await waitFor { fixture.probe.started.count == 2 }
        #expect(fixture.probe.started.filter { $0 == 10 }.count == 1)
        #expect(store.state.metrics.session == session)
        #expect(store.state.metrics.history.entries.count == 1)
        store.send(.metrics(.setMenuVisibility(false)))
        try await waitFor { fixture.probe.stopped == [20] }
        #expect(store.state.metrics.sample == sample)
        #expect(store.state.metrics.history.entries.count == 1)
        #expect(fixture.probe.refreshStarts == 1)
        #expect(fixture.probe.refreshStops == 0)
        store.send(.metrics(.setVisibility(fixture.first.identifier, false)))
        try await waitFor { fixture.probe.stopped.count == 2 && fixture.probe.refreshStops == 1 }
    }

    @Test
    func `closing details keeps menu values while detail history stays empty`() async throws {
        let fixture = try Fixture()
        let store = try fixture.store()
        store.send(.metrics(.setMenuVisibility(true)))
        try await waitFor { fixture.probe.started.count == 2 }
        let sample = makeSample(pid: 10)
        fixture.probe.yield(.sample(sample), pid: 10)
        try await waitFor { store.state.metrics.processes[10]?.sample == sample }
        store.send(.metrics(.setVisibility(fixture.first.identifier, true)))
        try await waitFor { store.state.metrics.sample == sample }
        #expect(store.state.metrics.history.entries.count == 1)
        #expect(fixture.probe.started.count == 2)
        store.send(.metrics(.setVisibility(fixture.first.identifier, false)))
        try await waitFor { store.state.metrics.session == nil }
        let next = makeSample(pid: 10)
        fixture.probe.yield(.sample(next), pid: 10)
        try await waitFor { store.state.metrics.processes[10]?.sample == next }
        #expect(store.state.metrics.sample == nil)
        #expect(store.state.metrics.history.entries.isEmpty)
        #expect(fixture.probe.stopped.isEmpty)
        store.send(.metrics(.setMenuVisibility(false)))
        try await waitFor { fixture.probe.stopped.count == 2 }
    }

    @Test
    func `PID changes and removed definitions release only their own subscriptions`() async throws {
        let fixture = try Fixture()
        let store = try fixture.store()
        store.send(.metrics(.setMenuVisibility(true)))
        try await waitFor { fixture.probe.started.count == 2 }
        let oldID = try #require(store.state.metrics.processes[10]?.id)
        var statuses = store.state.statuses
        statuses[fixture.first.identifier] = .init(
            identifier: fixture.first.identifier, registration: .enabled, runtime: .running(pid: 11),
        )
        store.send(.receiveServices(.success(.init(
            services: store.state.services, statuses: statuses, statusFailures: [],
        ))))
        store.send(.metrics(.receive(oldID, .sample(makeSample(pid: 10)))))
        try await waitFor { Set(fixture.probe.started) == [10, 11, 20] && fixture.probe.stopped == [10] }
        #expect(store.state.metrics.processes[10] == nil)
        #expect(fixture.probe.started.filter { $0 == 20 }.count == 1)
        store.send(.receiveServices(.success(.init(
            services: [fixture.first], statuses: statuses, statusFailures: [],
        ))))
        try await waitFor { Set(fixture.probe.stopped) == [10, 20] }
        #expect(Set(store.state.metrics.processes.keys) == [11])
        store.send(.metrics(.setMenuVisibility(false)))
        try await waitFor { fixture.probe.stopped.count == 3 }
    }

    @Test
    func `definitions sharing a PID use one subscription`() async throws {
        let fixture = try Fixture()
        let store = try fixture.store()
        store.state.statuses[fixture.second.identifier] = .init(
            identifier: fixture.second.identifier, registration: .enabled, runtime: .running(pid: 10),
        )
        store.send(.metrics(.setMenuVisibility(true)))
        try await waitFor { fixture.probe.started == [10] }
        #expect(store.state.metrics.processes.count == 1)
        store.send(.metrics(.setMenuVisibility(false)))
        try await waitFor { fixture.probe.stopped == [10] }
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
        let first: ServiceDefinition
        let second: ServiceDefinition
        let probe = MetricsProbe()

        init() throws {
            first = try Self.service("api")
            second = try Self.service("worker", kind: .launchDaemon)
        }

        func store() throws -> some Store<ServicesState, ServicesAction> {
            let waiting = try Self.service("waiting")
            let disabled = try Self.service("disabled", kind: .launchDaemon)
            let state = ServicesState()
            state.services = [first, second, waiting, disabled]
            state.selectedIdentifier = first.identifier
            state.statuses = [
                first.identifier: .init(
                    identifier: first.identifier, registration: .enabled, runtime: .running(pid: 10),
                ),
                second.identifier: .init(
                    identifier: second.identifier, registration: .enabled, runtime: .running(pid: 20),
                ),
                waiting.identifier: .init(identifier: waiting.identifier, registration: .enabled, runtime: .waiting),
                disabled.identifier: .init(
                    identifier: disabled.identifier, registration: .disabled, runtime: .notLoaded,
                ),
            ]
            return StoreBuilder.reducer(initialState: state, reducer: ServicesReducer(dependencies: .init(
                serviceManagementUseCase: TestServiceManagementUseCase(), metricsClient: probe.client,
            )))
        }

        private static func service(
            _ identifier: String, kind: ServiceKind = .launchAgent,
        ) throws -> ServiceDefinition {
            try ServiceDefinition(
                identifier: ServiceIdentifier(identifier), kind: kind, programArguments: ["/usr/bin/true"],
                standardOutPath: "/tmp/test.out", standardErrorPath: "/tmp/test.err",
            )
        }
    }
}
