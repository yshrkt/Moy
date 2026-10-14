import Foundation
import MoyKit

enum ServicesAction: Sendable {
    case appear
    case refreshServices
    case receiveServices(Result<ServicesSnapshot, ServicesFailure>)
    case selectService(ServiceIdentifier?)

    case presentCreateService
    case presentEditService(ServiceIdentifier)
    case importService
    case receiveImportService(Result<ServiceDraft?, ServicesFailure>)
    case exportService(ServiceIdentifier)
    case receiveExportService(ServiceIdentifier, Result<Void, ServicesFailure>)
    case editor(ServiceEditorAction)
    case receiveSave(UUID, ServiceIdentifier, Result<Void, ServicesFailure>)

    case enableService(ServiceIdentifier)
    case disableService(ServiceIdentifier)
    case restartService(ServiceIdentifier)
    case receiveServiceOperation(ServiceIdentifier, Result<Void, ServicesFailure>)

    case requestDeleteService(ServiceIdentifier)
    case cancelDeleteService
    case confirmDeleteService
    case receiveDeleteService(ServiceIdentifier, Result<Void, ServicesFailure>)

    case openLog(String)
    case revealLog(String)
    case receiveFileOperation(Result<Void, ServicesFailure>)
    case dismissFailure
    case copyValue(String, item: String, identifier: ServiceIdentifier)
    case receiveCopyValue(CopyToast)
    case dismissCopyToast(UUID)
    case clearCopyFeedback
}
