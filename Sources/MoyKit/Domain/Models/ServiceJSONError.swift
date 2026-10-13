import Foundation

public enum ServiceJSONError: Error, Equatable, Sendable {
    case invalidDocument(reason: String)
    case unsupportedSchema(found: Int, supported: Int)
}

extension ServiceJSONError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidDocument(reason):
            "Invalid service JSON: \(reason)"
        case let .unsupportedSchema(found, supported):
            "Unsupported service JSON schema \(found); this version supports schema \(supported)."
        }
    }
}
