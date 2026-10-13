import Foundation

public protocol ServiceTransferUseCase: Sendable {
    func readService(from url: URL) async throws -> ServiceDraft
    func importService(from url: URL, enable: Bool) async throws -> ServiceDefinition
    func exportService(identifier: ServiceIdentifier, to url: URL) async throws
}
