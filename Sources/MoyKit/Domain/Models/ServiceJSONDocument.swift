import Foundation

public struct ServiceJSONDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var service: ServiceDefinition

    public init(service: ServiceDefinition) {
        schemaVersion = Self.currentSchemaVersion
        self.service = service
    }

    public init(from decoder: any Decoder) throws {
        let keys = try decoder.container(keyedBy: JSONKey.self)
        try Self.rejectUnknownKeys(keys, allowed: ["schemaVersion", "service"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw ServiceJSONError.unsupportedSchema(found: schemaVersion, supported: Self.currentSchemaVersion)
        }
        let serviceKeys = try keys.nestedContainer(keyedBy: JSONKey.self, forKey: JSONKey("service"))
        try Self.rejectUnknownKeys(serviceKeys, allowed: [
            "identifier", "kind", "displayName", "description", "programArguments", "workingDirectory",
            "environmentVariables", "runAtLoad", "keepAlive", "throttleInterval",
            "standardOutPath", "standardErrorPath",
        ])
        service = try container.decode(ServiceDefinition.self, forKey: .service)
    }

    public var draft: ServiceDraft {
        ServiceDraft(
            identifier: service.identifier,
            displayName: service.displayName,
            description: service.description,
            programArguments: service.programArguments,
            workingDirectory: service.workingDirectory,
            environmentVariables: service.environmentVariables,
            runAtLoad: service.runAtLoad,
            keepAlive: service.keepAlive,
            throttleInterval: service.throttleInterval,
            standardOutPath: service.standardOutPath.isEmpty ? nil : service.standardOutPath,
            standardErrorPath: service.standardErrorPath.isEmpty ? nil : service.standardErrorPath,
        )
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case service
    }

    private static func rejectUnknownKeys(_ container: KeyedDecodingContainer<JSONKey>, allowed: Set<String>) throws {
        let unknown = container.allKeys.map(\.stringValue).filter { !allowed.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "Unknown keys: \(unknown.joined(separator: ", "))",
            ))
        }
    }
}

private struct JSONKey: CodingKey {
    let stringValue: String
    var intValue: Int? {
        nil
    }

    init(_ value: String) {
        stringValue = value
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}
