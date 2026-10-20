import Foundation
import MoyKit
import Testing

struct CLIListTableTests {
    @Test
    func `aligns headers and rows and shows service kinds`() throws {
        let services = try [
            service("api", name: "API"),
            service("gpu-config", name: "GPU Config", kind: .launchDaemon),
        ]
        #expect(try render(services) == """
        IDENTIFIER  KIND          NAME        PROGRAM
        api         LaunchAgent   API         /usr/bin/true
        gpu-config  LaunchDaemon  GPU Config  /usr/bin/true
        """)
    }

    @Test(arguments: [
        (String(repeating: "a", count: 30), String(repeating: "a", count: 30), 2),
        (String(repeating: "a", count: 31), String(repeating: "a", count: 29) + "…", 2),
        (String(repeating: "日", count: 15), String(repeating: "日", count: 15), 2),
        (String(repeating: "日", count: 16), String(repeating: "日", count: 14) + "…", 2),
        (String(repeating: "e\u{301}", count: 31), String(repeating: "e\u{301}", count: 29) + "…", 2),
        (String(repeating: "👩‍💻", count: 16), String(repeating: "👩‍💻", count: 14) + "…", 2),
        (String(repeating: "日", count: 14) + "ab", String(repeating: "日", count: 14) + "ab", 2),
    ])
    func `limits names by display width without splitting characters`(
        input: String, expected: String, padding: Int,
    ) throws {
        let rendered = try render([service("example", name: input)])
        let row = try #require(rendered.split(separator: "\n").last)
        let suffix = String(repeating: " ", count: padding) + "/usr/bin/true"
        #expect(row == "example     LaunchAgent  " + expected + suffix)
    }

    @Test
    func `aligns mixed width names and preserves identifiers and programs`() throws {
        let identifier = String(repeating: "a", count: 64)
        let program = "/very/long/path/" + String(repeating: "program", count: 20)
        let services = try [
            service(identifier, name: "日本語", program: program),
            service("short", name: "Name"),
        ]
        let rows = try render(services).split(separator: "\n")
        #expect(rows[0] == "IDENTIFIER" + String(repeating: " ", count: 56) + "KIND         NAME    PROGRAM")
        #expect(rows.contains(Substring(identifier + "  LaunchAgent  日本語  " + program)))
        let shortRow = "short" + String(repeating: " ", count: 61) + "LaunchAgent  Name    /usr/bin/true"
        #expect(rows.contains(Substring(shortRow)))
    }

    @Test
    func `keeps names on one line and falls back to the identifier`() throws {
        let services = try [service("line", name: "A\tB\nC\rD"), service("fallback")]
        #expect(try render(services) == """
        IDENTIFIER  KIND         NAME      PROGRAM
        line        LaunchAgent  A B C D   /usr/bin/true
        fallback    LaunchAgent  fallback  /usr/bin/true
        """)
    }

    private func render(_ services: [ServiceDefinition]) throws -> String {
        var output = ""
        try withTemporaryEnvironment { environment in
            let directory = try URL(filePath: #require(environment["MOY_DATA_DIRECTORY"]))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            struct Store: Encodable {
                let schemaVersion = 1
                let services: [ServiceDefinition]
            }
            let data = try JSONEncoder().encode(Store(services: services))
            try data.write(to: directory.appending(path: "services.json"))
            let result = try runCLI(["list"], environment: environment)
            #expect(result.status == 0)
            #expect(result.standardError.isEmpty)
            output = String(result.standardOutput.dropLast())
        }
        return output
    }

    private func service(
        _ identifier: String, name: String? = nil, kind: ServiceKind = .launchAgent,
        program: String = "/usr/bin/true",
    ) throws -> ServiceDefinition {
        try ServiceDefinition(
            identifier: ServiceIdentifier(identifier), kind: kind, displayName: name,
            programArguments: [program],
            standardOutPath: "/tmp/moy.stdout.log", standardErrorPath: "/tmp/moy.stderr.log",
        )
    }
}
