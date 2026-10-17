import MoyKit

enum ServicesDeletionAction: Sendable {
    case request(ServiceIdentifier)
    case cancel
    case confirm
    case receive(ServiceIdentifier, Result<Void, ServicesFailure>)
}
