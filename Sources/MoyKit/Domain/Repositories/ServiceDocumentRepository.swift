import Foundation

public protocol ServiceDocumentRepository: Sendable {
    func read(from url: URL) async throws -> ServiceJSONDocument
    func write(_ document: ServiceJSONDocument, to url: URL) async throws
}
