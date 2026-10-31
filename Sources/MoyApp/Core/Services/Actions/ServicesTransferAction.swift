import MoyKit

enum ServicesTransferAction: Sendable {
    case duplicateService(ServiceIdentifier)
    case receiveDuplicate(ServiceIdentifier, Result<ServiceDraft, ServicesFailure>)
    case importService
    case receiveImport(Result<ServiceDraft?, ServicesFailure>)
    case exportService(ServiceIdentifier)
    case receiveExport(ServiceIdentifier, Result<Void, ServicesFailure>)
}
