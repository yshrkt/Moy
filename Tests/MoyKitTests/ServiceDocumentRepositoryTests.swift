import Foundation
@testable import MoyKit
import Testing

struct ServiceDocumentRepositoryTests {
    @Test
    func `document keeps all settings and omits nil optional keys`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let repository = JSONServiceDocumentRepository()
        let url = fixture.root.appending(path: "service.json")
        let service = try fixtureService()
        try await repository.write(ServiceJSONDocument(service: service), to: url)
        #expect(try await repository.read(from: url).service == service)

        var minimal = service
        minimal.displayName = nil
        minimal.description = nil
        minimal.workingDirectory = nil
        minimal.throttleInterval = nil
        minimal.standardOutPath = ""
        minimal.standardErrorPath = ""
        try await repository.write(ServiceJSONDocument(service: minimal), to: url)
        let data = try Data(contentsOf: url)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let settings = try #require(root["service"] as? [String: Any])
        for key in ["displayName", "description", "workingDirectory", "throttleInterval"] {
            #expect(settings[key] == nil)
        }
        #expect(settings["standardOutPath"] as? String == "")
        #expect(settings["standardErrorPath"] as? String == "")
        #expect(settings["Label"] == nil)
        #expect(settings["registration"] == nil)
        #expect(data.last == 0x0A)
        let draft = try await repository.read(from: url).draft
        #expect(draft.standardOutPath == nil)
        #expect(draft.standardErrorPath == nil)
    }

    @Test(arguments: [
        "unknownRoot", "unknownSetting", "missingLog", "nullLog", "wrongLogType", "missingKind", "unknownKind",
        "missingBoolean", "wrongBooleanType", "invalidIdentifier", "wrongArgumentsType", "missingSchema",
    ])
    func `rejects malformed documents and unknown keys`(mutation: String) async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let url = fixture.root.appending(path: "invalid.json")
        let encoded = try JSONEncoder().encode(ServiceJSONDocument(service: fixtureService()))
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var service = try #require(root["service"] as? [String: Any])
        let changes: [String: (key: String, value: Any?)] = [
            "unknownSetting": ("Label", "custom-label"),
            "missingLog": ("standardOutPath", nil),
            "nullLog": ("standardOutPath", NSNull()),
            "wrongLogType": ("standardOutPath", 42),
            "missingKind": ("kind", nil),
            "unknownKind": ("kind", "unknownKind"),
            "missingBoolean": ("runAtLoad", nil),
            "wrongBooleanType": ("runAtLoad", "true"),
            "invalidIdentifier": ("identifier", "Invalid"),
            "wrongArgumentsType": ("programArguments", "/usr/bin/true"),
        ]
        if mutation == "unknownRoot" {
            root["services"] = []
        } else if mutation == "missingSchema" {
            root.removeValue(forKey: "schemaVersion")
        } else if let change = changes[mutation] {
            service[change.key] = change.value
        }
        root["service"] = service
        try JSONSerialization.data(withJSONObject: root).write(to: url)
        await #expect(throws: ServiceJSONError.self) {
            _ = try await JSONServiceDocumentRepository().read(from: url)
        }
    }

    @Test
    func `rejects future schemas and invalid JSON syntax`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let url = fixture.root.appending(path: "invalid.json")
        try Data("{\"schemaVersion\":2,\"service\":{}}".utf8).write(to: url)
        await #expect(throws: ServiceJSONError.unsupportedSchema(found: 2, supported: 1)) {
            _ = try await JSONServiceDocumentRepository().read(from: url)
        }
        try Data("not json".utf8).write(to: url)
        await #expect(throws: ServiceJSONError.self) {
            _ = try await JSONServiceDocumentRepository().read(from: url)
        }
    }

    @Test
    func `null optional fields and arbitrary environment keys are supported`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let url = fixture.root.appending(path: "service.json")
        let encoded = try JSONEncoder().encode(ServiceJSONDocument(service: fixtureService()))
        var root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var service = try #require(root["service"] as? [String: Any])
        for key in ["displayName", "description", "workingDirectory", "throttleInterval"] {
            service[key] = NSNull()
        }
        service["environmentVariables"] = ["service": "a=b", "schemaVersion": "$VALUE"]
        root["service"] = service
        try JSONSerialization.data(withJSONObject: root).write(to: url)
        let result = try await JSONServiceDocumentRepository().read(from: url)
        #expect(result.service.displayName == nil)
        #expect(result.service.description == nil)
        #expect(result.service.workingDirectory == nil)
        #expect(result.service.throttleInterval == nil)
        #expect(result.service.environmentVariables == ["service": "a=b", "schemaVersion": "$VALUE"])
    }

    @Test
    func `overwrites existing output and reports unusable paths`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let repository = JSONServiceDocumentRepository()
        let document = try ServiceJSONDocument(service: fixtureService())
        let url = fixture.root.appending(path: "service.json")
        try Data("old output".utf8).write(to: url)
        try await repository.write(document, to: url)
        #expect(try await repository.read(from: url) == document)
        await #expect(throws: MoyError.self) {
            try await repository.write(document, to: fixture.root)
        }
        await #expect(throws: MoyError.self) {
            try await repository.write(document, to: fixture.root.appending(path: "missing/service.json"))
        }
        await #expect(throws: MoyError.self) {
            _ = try await repository.read(from: fixture.root.appending(path: "missing.json"))
        }
        #expect(try await repository.read(from: url) == document)
    }
}
