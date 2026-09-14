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
        let bytes = Array(value.utf8)
        guard 1 ... maximumLength ~= bytes.count,
              let first = bytes.first,
              let last = bytes.last,
              isAlphanumeric(first),
              isAlphanumeric(last)
        else {
            return false
        }
        return bytes.allSatisfy { isAlphanumeric($0) || $0 == 45 || $0 == 95 }
    }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        (97 ... 122).contains(byte) || (48 ... 57).contains(byte)
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
