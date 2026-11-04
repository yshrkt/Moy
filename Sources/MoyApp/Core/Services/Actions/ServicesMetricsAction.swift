import Foundation
import MoyKit

enum ServicesMetricsAction: Sendable {
    case setVisibility(ServiceIdentifier, Bool)
    case receive(UUID, ServicesMetricsEvent)
}
