import Foundation
import MoyKit

enum ServicesAction: Sendable {
    case appear
    case refreshServices
    case receiveServices(Result<ServicesSnapshot, ServicesFailure>)
    case selectService(ServiceIdentifier?)

    case presentCreateService
    case presentEditService(ServiceIdentifier)
    case dismissEditor
    case updateEditor(ServiceEditorField)
    case selectArgument(UUID?)
    case moveArgument(UUID, toIndex: Int)
    case dropArgument(UUID, insertionIndex: Int)
    case addArgument
    case updateArgument(UUID, String)
    case removeArgument(UUID)
    case selectEnvironmentVariable(UUID?)
    case addEnvironmentVariable
    case updateEnvironmentKey(UUID, String)
    case updateEnvironmentValue(UUID, String)
    case removeEnvironmentVariable(UUID)
    case chooseEditorPath(ServiceEditorPath)
    case receiveEditorPath(ServiceEditorPath, String?)
    case saveService(enable: Bool)
    case receiveSave(ServiceIdentifier, Result<Void, ServicesFailure>)

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
