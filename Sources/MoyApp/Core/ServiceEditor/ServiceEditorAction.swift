import Foundation
import MoyKit

enum ServiceEditorAction: Sendable {
    case cancel
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
    case receiveEditorPath(UUID, ServiceEditorPath, String?)
    case saveService(enable: Bool)
    case dismissFailure
    case receiveSave(Result<Void, ServicesFailure>)
    case delegate(Delegate)

    enum Delegate: Sendable {
        case cancel(UUID)
        case save(UUID, ServiceEditorPayload, enable: Bool)
    }
}
