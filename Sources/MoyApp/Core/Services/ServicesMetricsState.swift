import Foundation
import MoyKit
import MoyMetrics

struct ServicesMetricsState {
    var visibleIdentifier: ServiceIdentifier?
    var session: ServicesMetricsSession?
    var sample: ProcessSample?
    var physicalMemory: UInt64?
    var history = ServicesMetricsHistory()
    var isUnavailable = false
}

struct ServicesMetricsSession: Equatable, Sendable {
    let id: UUID
    let identifier: ServiceIdentifier
    let pid: Int32
}
