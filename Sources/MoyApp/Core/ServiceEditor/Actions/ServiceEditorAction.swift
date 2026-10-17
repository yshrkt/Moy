import Foundation
import MoyKit

enum ServiceEditorAction: Sendable {
    case cancel
    case updateField(ServiceEditorField)
    case updateExistingIdentifiers(Set<String>)
    case receiveIdentifierValidation(UUID, String, ServiceEditorIdentifierIssue?)
    case arguments(ServiceEditorArgumentsAction)
    case environment(ServiceEditorEnvironmentAction)
    case choosePath(ServiceEditorPath)
    case receivePath(UUID, ServiceEditorPath, String?)
    case save
    case dismissFailure
    case receiveSave(Result<Void, ServicesFailure>)
    case delegate(Delegate)

    enum Delegate: Sendable {
        case cancel(UUID)
        case save(UUID, ServiceEditorPayload)
    }
}
