import Foundation

public actor DefaultServiceTransferUseCase: ServiceTransferUseCase {
    private let serviceManagementUseCase: any ServiceManagementUseCase
    private let documentRepository: any ServiceDocumentRepository
    private let paths: MoyPaths

    public init(
        serviceManagementUseCase: any ServiceManagementUseCase,
        documentRepository: any ServiceDocumentRepository = JSONServiceDocumentRepository(),
        paths: MoyPaths = .defaults(),
    ) {
        self.serviceManagementUseCase = serviceManagementUseCase
        self.documentRepository = documentRepository
        self.paths = paths
    }

    public func readService(from url: URL) async throws -> ServiceDraft {
        try await documentRepository.read(from: url).draft
    }

    public func importService(from url: URL, enable: Bool = false) async throws -> ServiceDefinition {
        let draft = try await readService(from: url)
        return try await serviceManagementUseCase.create(draft, enable: enable)
    }

    public func exportService(identifier: ServiceIdentifier, to url: URL) async throws {
        var service = try await serviceManagementUseCase.find(identifier: identifier)
        if service.standardOutPath == paths.standardOutFile(identifier: identifier).path {
            service.standardOutPath = ""
        }
        if service.standardErrorPath == paths.standardErrorFile(identifier: identifier).path {
            service.standardErrorPath = ""
        }
        try await documentRepository.write(ServiceJSONDocument(service: service), to: url)
    }
}
