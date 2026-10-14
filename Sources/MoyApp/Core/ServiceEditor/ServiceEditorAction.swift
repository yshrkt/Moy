import Foundation
import MoyKit

enum ServiceEditorAction: Sendable {
    case cancel
    case updateEditor(ServiceEditorField)
    case updateExistingIdentifiers(Set<String>)
    case receiveIdentifierValidation(UUID, String, ServiceEditorIdentifierIssue?)
    case arguments(ServiceEditorArgumentsAction)
    case environment(ServiceEditorEnvironmentAction)
    case chooseEditorPath(ServiceEditorPath)
    case receiveEditorPath(UUID, ServiceEditorPath, String?)
    case saveService
    case dismissFailure
    case receiveSave(Result<Void, ServicesFailure>)
    case delegate(Delegate)

    enum Delegate: Sendable {
        case cancel(UUID)
        case save(UUID, ServiceEditorPayload)
    }
}
