import Foundation
@testable import MoyKit
import Testing

struct ServiceDefinitionTests {
    @Test
    func `identifier validates and creates launchd label`() throws {
        let identifier = try ServiceIdentifier("api-server_2")

        #expect(identifier.rawValue == "api-server_2")
        #expect(identifier.launchdLabel == "com.sputnik-apps.moy.api-server_2")
        #expect(throws: MoyError.self) { try ServiceIdentifier("API") }
        #expect(throws: MoyError.self) { try ServiceIdentifier("-api") }
        #expect(throws: MoyError.self) { try ServiceIdentifier(String(repeating: "a", count: 65)) }
    }

    @Test
    func `plist contains the nine supported keys`() throws {
        let service = try fixtureService()
        let data = try LaunchdPlistWriter().data(for: service)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
        )

        #expect(Set(plist.keys) == [
            "Label",
            "ProgramArguments",
            "WorkingDirectory",
            "EnvironmentVariables",
            "RunAtLoad",
            "KeepAlive",
            "ThrottleInterval",
            "StandardOutPath",
            "StandardErrorPath",
        ])
        #expect(plist["ProgramArguments"] as? [String] == ["/usr/bin/printf", "hello world", ""])
        #expect(plist["EnvironmentVariables"] as? [String: String] == ["MODE": "test"])
    }

    @Test
    func `validator rejects relative executable`() throws {
        var service = try fixtureService()
        service.programArguments[0] = "printf"

        #expect(throws: MoyError.self) {
            try ServiceValidator.validate(service)
        }
    }

    @Test
    func `validator rejects a blank display name when provided`() throws {
        var service = try fixtureService()
        service.displayName = "  \n"

        #expect(throws: MoyError.self) {
            try ServiceValidator.validate(service)
        }
    }
}

func fixtureService(identifier: String = "fixture-service") throws -> ServiceDefinition {
    try ServiceDefinition(
        identifier: ServiceIdentifier(identifier),
        displayName: "Fixture",
        description: "A fixture service",
        programArguments: ["/usr/bin/printf", "hello world", ""],
        workingDirectory: "/tmp",
        environmentVariables: ["MODE": "test"],
        runAtLoad: true,
        keepAlive: false,
        throttleInterval: 12,
        standardOutPath: "/tmp/fixture.stdout.log",
        standardErrorPath: "/tmp/fixture.stderr.log",
    )
}
