import Foundation

public actor JSONServiceDocumentRepository: ServiceDocumentRepository {
    public init() {}

    public func read(from url: URL) async throws -> ServiceJSONDocument {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MoyError.fileOperation(path: url.path, reason: error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(ServiceJSONDocument.self, from: data)
        } catch let error as ServiceJSONError {
            throw error
        } catch let error as DecodingError {
            throw ServiceJSONError.invalidDocument(reason: Self.describe(error))
        } catch {
            throw ServiceJSONError.invalidDocument(reason: error.localizedDescription)
        }
    }

    public func write(_ document: ServiceJSONDocument, to url: URL) async throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(document)
            data.append(0x0A)
            try data.write(to: url, options: .atomic)
        } catch {
            throw MoyError.fileOperation(path: url.path, reason: error.localizedDescription)
        }
    }

    private static func describe(_ error: DecodingError) -> String {
        let context: DecodingError.Context
        let suffix: [String]
        switch error {
        case let .keyNotFound(key, details):
            context = details
            suffix = [key.stringValue]
        case let .typeMismatch(_, details), let .valueNotFound(_, details), let .dataCorrupted(details):
            context = details
            suffix = []
        @unknown default:
            return error.localizedDescription
        }
        let path = (context.codingPath.map(\.stringValue) + suffix).joined(separator: ".")
        return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
    }
}
