import Foundation
import Testing

struct CLIEndToEndTests {
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

            let remove = try runCLI(["remove", identifier], environment: environment)
            #expect(remove.status == 0)

            let emptyList = try runCLI(["list", "--json"], environment: environment)
            let emptyData = try #require(emptyList.standardOutput.data(using: .utf8))
            let emptyServices = try #require(JSONSerialization.jsonObject(with: emptyData) as? [[String: Any]])
            #expect(emptyServices.isEmpty)
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

private struct CLIResult {
    let status: Int32
    let standardOutput: String
    let standardError: String
}

private final class TestBundleToken: NSObject {}

private func runCLI(_ arguments: [String], environment: [String: String]) throws -> CLIResult {
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

private func withTemporaryEnvironment(_ body: ([String: String]) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "MoyCLITests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    try body([
        "MOY_DATA_DIRECTORY": root.appending(path: "data").path,
        "MOY_LAUNCH_AGENTS_DIRECTORY": root.appending(path: "launch-agents").path,
        "MOY_LOG_DIRECTORY": root.appending(path: "logs").path,
    ])
}
