import Foundation
@testable import MoyApp
import MoyKit
import MoyMetrics
import Testing

struct ServicesMetricsHistoryTests {
    @Test
    func `history keeps only the last minute with a bounded number of points`() {
        var history = ServicesMetricsHistory()
        for second in stride(from: 0, through: 120, by: 2) {
            history.append(sample(second: Double(second)))
        }
        #expect(history.entries.count == 31)
        #expect(history.entries.first?.timestamp == Date(timeIntervalSince1970: 60))
        #expect(history.entries.last?.timestamp == Date(timeIntervalSince1970: 120))
        for index in 1 ... 100 {
            history.append(sample(second: 120 + Double(index) / 1000))
        }
        #expect(history.entries.count == 31)
    }

    @Test
    func `clock changes start a new history instead of joining times out of order`() {
        var history = ServicesMetricsHistory()
        history.append(sample(second: 100))
        history.append(sample(second: 90))
        #expect(history.entries.map(\.timestamp) == [Date(timeIntervalSince1970: 90)])
        history.append(sample(second: 90))
        #expect(history.entries.count == 1)
    }

    @Test
    func `missing values and long gaps split lines independently for each metric`() {
        var history = ServicesMetricsHistory()
        history.append(sample(second: 0))
        history.append(sample(second: 2, cpu: .failed(.counterOverflow)))
        history.append(sample(second: 4))
        history.append(sample(second: 12))
        let cpu = ServiceMetricChartData(history: history, metric: .cpu)
        let memory = ServiceMetricChartData(history: history, metric: .memory)
        #expect(cpu.points.map(\.segment) == [0, 1, 2])
        #expect(memory.points.map(\.segment) == [0, 0, 0, 1])
        #expect(cpu.points.count == 3)
        #expect(memory.points.count == 4)
    }

    @Test
    func `CPU ranges cover 100 percent plus and memory zooms into observed usage`() {
        var history = ServicesMetricsHistory()
        history.append(sample(second: 0, cpu: .value(250)))
        history.append(sample(second: 2, cpu: .value(10)))
        let cpu = ServiceMetricChartData(history: history, metric: .cpu)
        let memory = ServiceMetricChartData(history: history, metric: .memory)
        #expect(cpu.valueDomain == 0 ... 300)
        #expect(cpu.timeDomain.upperBound.timeIntervalSince(cpu.timeDomain.lowerBound) == 60)
        #expect(memory.valueDomain.lowerBound > 0)
        #expect(memory.valueDomain.contains(128 * 1024 * 1024))
        #expect(ServiceMetricChartData(history: .init(), metric: .cpu).valueDomain == 0 ... 100)
        #expect(ServiceMetricChartData(history: .init(), metric: .memory).valueDomain.lowerBound == 0)
    }

    @Test
    func `invalid CPU values leave gaps instead of reaching chart scales`() {
        var history = ServicesMetricsHistory()
        for (index, value) in [Double.nan, .infinity, -1].enumerated() {
            history.append(sample(second: Double(index) * 2, cpu: .value(value)))
        }
        #expect(ServiceMetricChartData(history: history, metric: .cpu).points.isEmpty)
        #expect(ServiceMetricChartData(history: history, metric: .memory).points.count == 3)
    }

    @Test
    func `accessibility range communicates the observed values`() throws {
        var history = ServicesMetricsHistory()
        history.append(sample(second: 0, cpu: .value(10)))
        history.append(sample(second: 2, cpu: .value(150)))
        let data = ServiceMetricChartData(history: history, metric: .cpu)
        let locale = Locale(identifier: "en_US")
        let description = ServiceResourceUsagePresentation.history(data, metric: .cpu, locale: locale)
        let value = try #require(description)
        #expect(value.contains("10.0%"))
        #expect(value.contains("150.0%"))
    }

    @MainActor
    @Test
    func `capacity and history follow the current session and survive ordinary status refresh`() throws {
        let service = try ServiceDefinition(
            identifier: ServiceIdentifier("worker"), programArguments: ["/usr/bin/true"],
            standardOutPath: "/tmp/worker.out", standardErrorPath: "/tmp/worker.err",
        )
        let reducer = ServicesReducer(dependencies: .init(
            serviceManagementUseCase: TestServiceManagementUseCase(), metricsClient: .idle,
        ))
        var state = ServicesState()
        state.services = [service]
        state.selectedIdentifier = service.identifier
        state.statuses[service.identifier] = .init(
            identifier: service.identifier, registration: .enabled, runtime: .running(pid: 10),
        )
        _ = reducer.reduce(into: &state, action: .metrics(.setVisibility(service.identifier, true)))
        let session = try #require(state.metrics.session)
        let capacity: UInt64 = 32 * 1024 * 1024 * 1024
        _ = reducer.reduce(into: &state, action: .metrics(.receive(session.id, .capacity(capacity))))
        _ = reducer.reduce(into: &state, action: .metrics(.receive(session.id, .sample(sample(second: 0)))))
        _ = reducer.reduce(into: &state, action: .metrics(.receive(session.id, .sample(sample(second: 2)))))
        _ = reducer.reduce(into: &state, action: .receiveServices(.success(.init(
            services: [service], statuses: state.statuses, statusFailures: [],
        ))))
        #expect(state.metrics.history.entries.count == 2)
        #expect(state.metrics.session?.id == session.id)
        #expect(state.metrics.physicalMemory == capacity)
        _ = reducer.reduce(into: &state, action: .metrics(.setVisibility(service.identifier, false)))
        #expect(state.metrics.history.entries.isEmpty)
        _ = reducer.reduce(into: &state, action: .metrics(.setVisibility(service.identifier, true)))
        _ = reducer.reduce(into: &state, action: .metrics(.receive(session.id, .sample(sample(second: 4)))))
        _ = reducer.reduce(into: &state, action: .metrics(.receive(session.id, .capacity(1))))
        #expect(state.metrics.history.entries.isEmpty)
        #expect(state.metrics.physicalMemory == capacity)
    }

    private func sample(second: Double, cpu: MetricValue<Double> = .value(12.3)) -> ProcessSample {
        makeSample(pid: 10, cpu: cpu, timestamp: Date(timeIntervalSince1970: second))
    }
}
