import Foundation
import MoyKit

enum ServicesMetricsAction: Sendable {
    case setVisibility(ServiceIdentifier, Bool)
    case setMenuVisibility(Bool)
    case receive(UUID, ServicesMetricsEvent)
}
