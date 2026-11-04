@testable import MoyApp

extension ServicesMetricsClient {
    static let idle = Self(
        events: { _ in AsyncStream { $0.finish() } },
        refreshTicks: { AsyncStream { $0.finish() } },
    )
}
