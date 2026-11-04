import MoyMetrics

struct ServicesMetricsClient: Sendable {
    let events: @Sendable (Int32) -> AsyncStream<ServicesMetricsEvent>
    let refreshTicks: @Sendable () -> AsyncStream<Void>
}

enum ServicesMetricsEvent: Sendable {
    case capacity(UInt64)
    case sample(ProcessSample)
    case ended
    case failed
}
