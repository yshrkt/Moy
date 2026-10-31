import Foundation
import MoyKit
import Testing

struct CLICopyTests {
    @Test(arguments: ServiceKind.allCases)
    func `copy creates a disabled service with preserved settings and new default logs`(kind: ServiceKind) throws {
        try withTemporaryEnvironment { environment in
            let source = "copy-source-" + UUID().uuidString.lowercased()
            let destination = "copy-target-" + UUID().uuidString.lowercased()
            let add = try runCLI([
                "add", "--identifier", source, "--kind", kind.rawValue,
                "--name", "Copied service", "--description", "Description", "--program", "/usr/bin/printf",
                "--arg", "", "--arg", "hello world", "--env", "TOKEN=a=b", "--working-directory", "/tmp",
                "--run-at-load", "--keep-alive", "--throttle-interval", "12", "--stderr", "/tmp/shared.stderr.log",
            ], environment: environment)
            #expect(add.status == 0)
            let result = try runCLI(["copy", source, destination], environment: environment)
            #expect(result.status == 0)
            #expect(result.standardOutput == "Copied \(source) to \(destination)\n")
            let show = try runCLI(["show", destination, "--json"], environment: environment)
            let data = try #require(show.standardOutput.data(using: .utf8))
            let copied = try JSONDecoder().decode(ServiceDefinition.self, from: data)
            #expect(copied.identifier.rawValue == destination)
            #expect(copied.kind == kind)
            #expect(copied.displayName == "Copied service")
            #expect(copied.description == "Description")
            #expect(copied.programArguments == ["/usr/bin/printf", "", "hello world"])
            #expect(copied.environmentVariables == ["TOKEN": "a=b"])
            #expect(copied.workingDirectory == "/tmp")
            #expect(copied.runAtLoad && copied.keepAlive)
            #expect(copied.throttleInterval == 12)
            let logs = try #require(environment["MOY_LOG_DIRECTORY"])
            #expect(copied.standardOutPath == "\(logs)/com.sputnik-apps.moy.\(destination).stdout.log")
            #expect(copied.standardErrorPath == "/tmp/shared.stderr.log")
            #expect(!FileManager.default.fileExists(atPath: logs))
            let agents = try #require(environment["MOY_LAUNCH_AGENTS_DIRECTORY"])
            #expect(!FileManager.default.fileExists(atPath: agents))
            let directory = try URL(filePath: #require(environment["MOY_DATA_DIRECTORY"]))
            let storage = directory.appending(path: "services.json")
            let before = try Data(contentsOf: storage)
            for arguments in [["copy", source, destination], ["copy", source, source],
                              ["copy", "missing", "new-target"], ["copy", source, "INVALID"]]
            {
                let failure = try runCLI(arguments, environment: environment)
                #expect(failure.status != 0)
                #expect(!failure.standardError.isEmpty)
                #expect(try Data(contentsOf: storage) == before)
            }
            let help = try runCLI(["copy", "--help"], environment: environment)
            #expect(help.status == 0)
            #expect(help.standardOutput.contains("--enable"))
        }
    }
}
