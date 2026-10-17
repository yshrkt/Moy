import Foundation
import MoyKit

enum ServicesAction: Sendable {
    case appear
    case refreshServices
    case receiveServices(Result<ServicesSnapshot, ServicesFailure>)
    case selectService(ServiceIdentifier?)

    case presentCreateService
    case presentEditService(ServiceIdentifier)
    case transfer(ServicesTransferAction)
    case editor(ServiceEditorAction)
    case receiveSave(UUID, ServiceIdentifier, Result<Void, ServicesFailure>)

    case operation(ServicesOperationAction)
    case deletion(ServicesDeletionAction)

    case openLog(String)
    case revealLog(String)
    case receiveFileOperation(Result<Void, ServicesFailure>)
    case dismissFailure
    case copyFeedback(ServicesCopyFeedbackAction)
}
