import Darwin
import Foundation
import MoyKit
import Testing

struct CLIEndToEndTests {
    @Test
    func `internal user log preparation creates files without enabling the daemon`() throws {
        try withTemporaryEnvironment { environment in
            let directory = try URL(filePath: #require(environment["MOY_LOG_DIRECTORY"]))
            let service = try ServiceDefinition(
                identifier: ServiceIdentifier("prepare-logs-cli"), kind: .launchDaemon,
                programArguments: ["/usr/bin/true"], standardOutPath: directory.appending(path: "stdout.log").path,
                standardErrorPath: directory.appending(path: "stderr.log").path,
            )
            let payload = try JSONEncoder().encode(UserRepositoryRequest.prepareLogs(service)).base64EncodedString()
            let result = try runCLI(["internal-repository", payload], environment: environment)
            #expect(result.status == 0)
            let data = try #require(result.standardOutput.data(using: .utf8))
            let response = try JSONDecoder().decode(UserRepositoryResponse.self, from: data)
            #expect(response.error == nil)
            for path in [service.standardOutPath, service.standardErrorPath] {
                let attributes = try FileManager.default.attributesOfItem(atPath: path)
                #expect(attributes[.ownerAccountID] as? UInt32 == getuid())
                #expect(try Data(contentsOf: URL(filePath: path)).isEmpty)
            }
            let definitions = try URL(filePath: #require(environment["MOY_DATA_DIRECTORY"]))
            #expect(!FileManager.default.fileExists(atPath: definitions.appending(path: "services.json").path))
        }
    }

    @Test
    func `daemon definitions are editable without sudo but enable fails before writes`() throws {
        try withTemporaryEnvironment { environment in
            let identifier = "daemon-cli-" + UUID().uuidString.lowercased()
            let add = try runCLI([
                "add", "--identifier", identifier, "--kind", "launchDaemon", "--program", "/usr/bin/true",
            ], environment: environment)
            #expect(add.status == 0)
            let directory = try URL(filePath: #require(environment["MOY_DATA_DIRECTORY"]))
            let storage = directory.appending(path: "services.json")
            let original = try Data(contentsOf: storage)
            let enable = try runCLI(["enable", identifier], environment: environment)
            #expect(enable.status != 0)
            #expect(enable.standardError.contains("sudo"))
            let logDirectory = try #require(environment["MOY_LOG_DIRECTORY"])
            #expect(!FileManager.default.fileExists(atPath: logDirectory))
            #expect(try Data(contentsOf: storage) == original)
            let edit = try runCLI(["edit", identifier, "--run-at-load", "true"], environment: environment)
            #expect(edit.status == 0)
            let show = try runCLI(["show", identifier, "--json"], environment: environment)
            let data = try #require(show.standardOutput.data(using: .utf8))
            let service = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(service["kind"] as? String == "launchDaemon")
            #expect(service["runAtLoad"] as? Bool == true)

            let logs = try #require(environment["MOY_LOG_DIRECTORY"])
            #expect((service["standardOutPath"] as? String)?.hasPrefix(logs + "/") == true)
            let exported = directory.appending(path: "exported.json")
            #expect(try runCLI(["export", identifier, "--output", exported.path], environment: environment).status == 0)
            let exportedData = try Data(contentsOf: exported)
            let document = try #require(JSONSerialization.jsonObject(with: exportedData) as? [String: Any])
            let exportedService = try #require(document["service"] as? [String: Any])
            #expect(exportedService["kind"] as? String == "launchDaemon")
            #expect(exportedService["standardOutPath"] as? String == "")
            #expect(try runCLI(["remove", identifier], environment: environment).status == 0)
        }
    }

    @Test
    func `adds lists and removes a service`() throws {
        try withTemporaryEnvironment { environment in
            let add = try runCLI(
                [
                    "add",
                    "--identifier", "web-server",
                    "--name", "Web server",
                    "--program", "/usr/bin/python3",
                    "--arg", "-m",
                    "--arg", "http.server",
                    "--env", "TOKEN=a=b=c",
                    "--run-at-load",
                ],
                environment: environment,
            )

            #expect(add.status == 0)
            #expect(add.standardOutput == "Added web-server\n")

            let list = try runCLI(["list", "--json"], environment: environment)
            let data = try #require(list.standardOutput.data(using: .utf8))
            let services = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            let service = try #require(services.first)
            let identifier = try #require(service["identifier"] as? String)

            #expect(list.status == 0)
            #expect(services.count == 1)
            #expect(identifier == "web-server")
            #expect(service["displayName"] as? String == "Web server")
            #expect(service["programArguments"] as? [String] == ["/usr/bin/python3", "-m", "http.server"])
            #expect(service["environmentVariables"] as? [String: String] == ["TOKEN": "a=b=c"])
            #expect(service["runAtLoad"] as? Bool == true)

            let table = try runCLI(["list"], environment: environment)
            #expect(table.status == 0)
            #expect(table.standardOutput == """
            IDENTIFIER  KIND         NAME        PROGRAM
            web-server  LaunchAgent  Web server  /usr/bin/python3

            """)

            let remove = try runCLI(["remove", identifier], environment: environment)
            #expect(remove.status == 0)

            let emptyList = try runCLI(["list", "--json"], environment: environment)
            let emptyData = try #require(emptyList.standardOutput.data(using: .utf8))
            let emptyServices = try #require(JSONSerialization.jsonObject(with: emptyData) as? [[String: Any]])
            #expect(emptyServices.isEmpty)
        }
    }

    @Test
    func `failed update application reports saved settings and leaves new JSON`() throws {
        try withTemporaryEnvironment { environment in
            let identifier = "apply-failure-" + UUID().uuidString.lowercased()
            let add = try runCLI(["add", "--identifier", identifier, "--program", "/usr/bin/true"],
                                 environment: environment)
            #expect(add.status == 0)
            let agents = try URL(filePath: #require(environment["MOY_LAUNCH_AGENTS_DIRECTORY"]))
            try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
            let plist = agents.appending(path: "com.sputnik-apps.moy.\(identifier).plist")
            try Data().write(to: plist)
            let dataDirectory = try URL(filePath: #require(environment["MOY_DATA_DIRECTORY"]))
            let blocked = dataDirectory.appending(path: "not-a-directory")
            try Data().write(to: blocked)
            let newLogPath = blocked.appending(path: "stdout.log").path

            let edit = try runCLI(["edit", identifier, "--stdout", newLogPath], environment: environment)
            #expect(edit.status != 0)
            #expect(edit.standardError.contains("Settings were saved, but could not be applied to the service."))
            #expect(edit.standardError.contains("disable it, then enable it again"))
            #expect(edit.standardError.contains("File operation failed"))
            let show = try runCLI(["show", identifier, "--json"], environment: environment)
            let data = try #require(show.standardOutput.data(using: .utf8))
            let service = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(service["standardOutPath"] as? String == newLogPath)
        }
    }

    @Test
    func `rejects malformed environment values`() throws {
        try withTemporaryEnvironment { environment in
            let result = try runCLI(
                [
                    "add", "--identifier", "invalid-environment", "--name", "Invalid environment",
                    "--program", "/usr/bin/true", "--env", "INVALID",
                ],
                environment: environment,
            )

            #expect(result.status != 0)
            #expect(result.standardError.contains("KEY=VALUE"))
        }
    }

    @Test
    func `requires an identifier when adding a service`() throws {
        try withTemporaryEnvironment { environment in
            let result = try runCLI(
                ["add", "--name", "True", "--program", "/usr/bin/true"],
                environment: environment,
            )

            #expect(result.status != 0)
            #expect(result.standardError.contains("--identifier"))
        }
    }

    @Test
    func `uses identifier as the display name fallback`() throws {
        try withTemporaryEnvironment { environment in
            let add = try runCLI(
                ["add", "--identifier", "true-service", "--program", "/usr/bin/true"],
                environment: environment,
            )
            let show = try runCLI(["show", "true-service"], environment: environment)

            #expect(add.status == 0)
            #expect(show.status == 0)
            #expect(show.standardOutput.contains("Name:               true-service"))
            #expect(show.standardOutput.contains("Launchd Label:      com.sputnik-apps.moy.true-service"))
        }
    }
}

struct CLIResult {
    let status: Int32
    let standardOutput: String
    let standardError: String
}

private final class TestBundleToken: NSObject {}

func runCLI(_ arguments: [String], environment: [String: String]) throws -> CLIResult {
    let executable = Bundle(for: TestBundleToken.self)
        .bundleURL
        .deletingLastPathComponent()
        .appending(path: "moy")
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    return CLIResult(
        status: process.terminationStatus,
        standardOutput: String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8,
        ) ?? "",
        standardError: String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8,
        ) ?? "",
    )
}

func withTemporaryEnvironment(_ body: ([String: String]) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "MoyCLITests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try body([
        "MOY_DATA_DIRECTORY": root.appending(path: "data").path,
        "MOY_LAUNCH_AGENTS_DIRECTORY": root.appending(path: "launch-agents").path,
        "MOY_LOG_DIRECTORY": root.appending(path: "logs").path,
    ])
}

extension CLIEndToEndTests {
    @Test
    func `exports and imports all settings into a separate environment without enabling`() throws {
        try withTemporaryEnvironment { source in
            let identifier = "json-transfer-" + UUID().uuidString.lowercased()
            let root = try URL(filePath: #require(source["MOY_DATA_DIRECTORY"])).deletingLastPathComponent()
            let file = root.appending(path: "service with spaces.json")
            let add = try runCLI([
                "add", "--identifier", identifier, "--name", "Imported service", "--description", "Service description",
                "--program", "/usr/bin/printf", "--arg", "", "--arg", "hello world", "--arg", "$PORT",
                "--env", "TOKEN=a=b", "--working-directory", "/tmp", "--run-at-load", "--keep-alive",
                "--throttle-interval", "12", "--stderr", "/tmp/custom service.stderr.log",
            ], environment: source)
            #expect(add.status == 0)
            try Data("previous export".utf8).write(to: file)
            let exported = try runCLI(["export", identifier, "--output", file.path], environment: source)
            #expect(exported.status == 0)
            #expect(exported.standardOutput == "Exported \(identifier) to \(file.path)\n")
            let document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            #expect(document["schemaVersion"] as? Int == 1)
            let service = try #require(document["service"] as? [String: Any])
            #expect(service["standardOutPath"] as? String == "")
            #expect(service["standardErrorPath"] as? String == "/tmp/custom service.stderr.log")
            #expect(service["registration"] == nil)
            #expect(service["Label"] == nil)

            try withTemporaryEnvironment { destination in
                let imported = try runCLI(["import", file.path], environment: destination)
                #expect(imported.status == 0)
                #expect(imported.standardOutput == "Imported \(identifier)\n")
                let show = try runCLI(["show", identifier, "--json"], environment: destination)
                let data = try #require(show.standardOutput.data(using: .utf8))
                let saved = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                try expectImportedSettings(saved, identifier: identifier, environment: destination)
                let agents = try URL(filePath: #require(destination["MOY_LAUNCH_AGENTS_DIRECTORY"]))
                let plist = agents.appending(path: "com.sputnik-apps.moy.\(identifier).plist")
                #expect(!FileManager.default.fileExists(atPath: plist.path))
                let dataDirectory = try URL(filePath: #require(destination["MOY_DATA_DIRECTORY"]))
                let storage = dataDirectory.appending(path: "services.json")
                let before = try Data(contentsOf: storage)
                let duplicate = try runCLI(["import", file.path], environment: destination)
                #expect(duplicate.status != 0)
                #expect(duplicate.standardError.contains("already exists"))
                #expect(try Data(contentsOf: storage) == before)
            }
        }
    }

    @Test(arguments: ["malformed", "futureSchema", "unknownKey", "missingLog", "missingExecutable", "blankLog"])
    func `invalid imports fail without registering`(mutation: String) throws {
        try withTemporaryEnvironment { environment in
            let root = try URL(filePath: #require(environment["MOY_DATA_DIRECTORY"])).deletingLastPathComponent()
            let file = root.appending(path: "invalid.json")
            var service: [String: Any] = [
                "identifier": "invalid-json-test", "kind": "launchAgent", "programArguments": ["/usr/bin/true"],
                "environmentVariables": [:] as [String: String], "runAtLoad": false, "keepAlive": false,
                "standardOutPath": "", "standardErrorPath": "",
            ]
            var schema = 1
            switch mutation {
            case "futureSchema": schema = 2
            case "unknownKey": service["Label"] = "custom-label"
            case "missingLog": service.removeValue(forKey: "standardOutPath")
            case "missingExecutable": service["programArguments"] = [root.appending(path: "missing-tool").path]
            case "blankLog": service["standardOutPath"] = " "
            default: break
            }
            let data = mutation == "malformed" ? Data("not json".utf8)
                : try JSONSerialization.data(withJSONObject: ["schemaVersion": schema, "service": service])
            try data.write(to: file)
            let result = try runCLI(["import", file.path, "--enable"], environment: environment)
            #expect(result.status != 0)
            #expect(!result.standardError.isEmpty)
            let list = try runCLI(["list", "--json"], environment: environment)
            let listed = try #require(list.standardOutput.data(using: .utf8))
            #expect(try (JSONSerialization.jsonObject(with: listed) as? [[String: Any]])?.isEmpty == true)
        }
    }

    @Test
    func `export requires an output and preserves existing files when the service is missing`() throws {
        try withTemporaryEnvironment { environment in
            let root = try URL(filePath: #require(environment["MOY_DATA_DIRECTORY"])).deletingLastPathComponent()
            let output = root.appending(path: "existing.json")
            let previous = Data("previous output".utf8)
            try previous.write(to: output)
            let missingOutput = try runCLI(["export", "missing-service"], environment: environment)
            #expect(missingOutput.status != 0)
            #expect(missingOutput.standardError.contains("--output"))
            let arguments = ["export", "missing-service", "--output", output.path]
            let missingService = try runCLI(arguments, environment: environment)
            #expect(missingService.status != 0)
            #expect(missingService.standardError.contains("Service not found"))
            #expect(try Data(contentsOf: output) == previous)
            let help = try runCLI(["import", "--help"], environment: environment)
            #expect(help.status == 0)
            #expect(help.standardOutput.contains("--enable"))
        }
    }
}

private func expectImportedSettings(_ saved: [String: Any], identifier: String, environment: [String: String]) throws {
    #expect(saved["kind"] as? String == "launchAgent")
    #expect(saved["displayName"] as? String == "Imported service")
    #expect(saved["description"] as? String == "Service description")
    #expect(saved["programArguments"] as? [String] == ["/usr/bin/printf", "", "hello world", "$PORT"])
    #expect(saved["environmentVariables"] as? [String: String] == ["TOKEN": "a=b"])
    #expect(saved["workingDirectory"] as? String == "/tmp")
    #expect(saved["runAtLoad"] as? Bool == true)
    #expect(saved["keepAlive"] as? Bool == true)
    #expect(saved["throttleInterval"] as? Int == 12)
    let logs = try #require(environment["MOY_LOG_DIRECTORY"])
    #expect(saved["standardOutPath"] as? String == "\(logs)/com.sputnik-apps.moy.\(identifier).stdout.log")
    #expect(saved["standardErrorPath"] as? String == "/tmp/custom service.stderr.log")
}
