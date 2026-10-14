import MoyKit

enum ServicesTransferAction: Sendable {
    case importService
    case receiveImportService(Result<ServiceDraft?, ServicesFailure>)
    case exportService(ServiceIdentifier)
    case receiveExportService(ServiceIdentifier, Result<Void, ServicesFailure>)
}
