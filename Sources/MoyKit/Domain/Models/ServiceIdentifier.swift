import Foundation

public struct ServiceIdentifier: Hashable, Sendable {
    public static let launchdLabelPrefix = "com.sputnik-apps.moy."
    public static let maximumLength = 64

    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard Self.isValid(rawValue) else {
            throw MoyError.invalidIdentifier(rawValue)
        }
        self.rawValue = rawValue
    }

    public var launchdLabel: String {
        Self.launchdLabelPrefix + rawValue
    }

    public static func isValid(_ value: String) -> Bool {
        validationIssue(for: value) == nil
    }

    public static func validationIssue(for value: String) -> ServiceIdentifierValidationIssue? {
        ServiceIdentifierValidator.validate(value)
    }
}

extension ServiceIdentifier: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        do {
            try self.init(rawValue)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid Moy service identifier: \(rawValue)",
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ServiceIdentifier: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}
