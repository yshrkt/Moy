import Foundation
import MoyKit

enum ServicesCopyFeedbackAction: Sendable {
    case copy(String, item: String, identifier: ServiceIdentifier)
    case receiveCopy(CopyToast)
    case dismissToast(UUID)
    case clear
}
