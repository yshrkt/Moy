import MoyKit

enum ServicesTransferAction: Sendable {
    case importService
    case receiveImport(Result<ServiceDraft?, ServicesFailure>)
    case exportService(ServiceIdentifier)
    case receiveExport(ServiceIdentifier, Result<Void, ServicesFailure>)
}
