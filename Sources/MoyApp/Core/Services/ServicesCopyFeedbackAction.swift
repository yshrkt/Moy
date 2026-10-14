import Foundation
import MoyKit

enum ServicesCopyFeedbackAction: Sendable {
    case copyValue(String, item: String, identifier: ServiceIdentifier)
    case receiveCopyValue(CopyToast)
    case dismissCopyToast(UUID)
    case clearCopyFeedback
}
