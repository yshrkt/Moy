import MoyKit

enum ServicesOperationAction: Sendable {
    case enable(ServiceIdentifier)
    case disable(ServiceIdentifier)
    case restart(ServiceIdentifier)
    case receive(ServiceIdentifier, Result<Void, ServicesFailure>)
}
