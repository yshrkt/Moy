import Foundation
@testable import MoyApp
import MoyKit
import Testing

@Suite("Authorized CLI installer")
struct AuthorizedCLIInstallerTests {
    @Test(arguments: ["installed", "cancelled", "conflict", "missing", "unexpected"])
    func `handle structured authorization results`(output: String) async throws {
        let runner = RecordingAppleScriptRunner(output: output)
        let installer = AuthorizedCLIInstaller(scriptClient: AppleScriptClient(execute: runner.execute))
        let source = URL(fileURLWithPath: "/Applications/Moy.app/Contents/Helpers/moy")
        let destination = URL(fileURLWithPath: CLIInstaller.installationPath)
        switch output {
        case "installed":
            try await installer.install(source: source, destination: destination)
        case "cancelled":
            await #expect(throws: CancellationError.self) {
                try await installer.install(source: source, destination: destination)
            }
        case "conflict":
            await #expect(throws: SettingsFailure.cliDestinationExists) {
                try await installer.install(source: source, destination: destination)
            }
        case "missing":
            await #expect(throws: SettingsFailure.cliNotBundled) {
                try await installer.install(source: source, destination: destination)
            }
        default:
            await #expect(throws: SettingsFailure.cliAuthorizationFailed(output)) {
                try await installer.install(source: source, destination: destination)
            }
        }
        let invocation = try #require(await runner.invocation)
        #expect(invocation.source == AuthorizedCLIInstaller.authorizationScript)
        #expect(invocation.handler == "installcli")
        #expect(invocation.arguments == [AuthorizedCLIInstaller.linkCommand(source: source, destination: destination)])
    }

    @Test
    func `authorization script failure is reported`() async throws {
        let installer = AuthorizedCLIInstaller(scriptClient: AppleScriptClient { _, _, _ in
            throw SettingsFailure.cliAuthorizationFailed("Authorization denied")
        })
        await #expect(throws: SettingsFailure.cliAuthorizationFailed("Authorization denied")) {
            try await installer.install(
                source: URL(fileURLWithPath: "/Applications/Moy.app/Contents/Helpers/moy"),
                destination: URL(fileURLWithPath: CLIInstaller.installationPath),
            )
        }
    }

    @Test
    func `link command treats special characters as literal paths and refuses existing link`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "moy-authorized-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "Moy's \"CLI\" $(printf unsafe) `printf unsafe`\nwith space")
        let destination = root.appending(path: "bin/moy")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        let runner = DefaultProcessRunner()
        let command = AuthorizedCLIInstaller.linkCommand(source: source, destination: destination)
        let first = try await runner.run(executable: "/bin/sh", arguments: ["-c", command])
        #expect(first.status == 0)
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
        #expect(target == source.path)
        let second = try await runner.run(executable: "/bin/sh", arguments: ["-c", command])
        #expect(second.status == 17)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path) == target)
    }

    @Test
    @MainActor
    func `authorization AppleScript compiles without requesting privileges`() throws {
        let script = try #require(NSAppleScript(source: AuthorizedCLIInstaller.authorizationScript))
        var errorInfo: NSDictionary?
        let compiled = script.compileAndReturnError(&errorInfo)
        #expect(compiled, "\(String(describing: errorInfo))")
    }

    @Test
    func `native AppleScript passes literal arguments to the handler`() async throws {
        let argument = "Moy's \"CLI\" $(printf unsafe) `printf unsafe`\nwith space 日本語"
        let output = try await AppleScriptClient.live.execute(
            "on echoArgument(value)\nreturn value\nend echoArgument",
            "echoArgument",
            [argument],
        )
        #expect(output == argument)
    }

    @Test
    func `native AppleScript reports execution errors`() async throws {
        await #expect(throws: SettingsFailure.cliAuthorizationFailed("Authorization denied")) {
            try await AppleScriptClient.live.execute(
                "on failRequest()\nerror \"Authorization denied\" number -1743\nend failRequest",
                "failRequest",
                [],
            )
        }
    }

    @Test
    func `native AppleScript executes installation handler without elevation in a temporary directory`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "moy-native-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "Moy's \"CLI\" $(printf unsafe)\nwith space")
        let destination = root.appending(path: "bin/moy")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        // Only remove elevation; exercise the production handler and argument descriptors.
        let script = AuthorizedCLIInstaller.authorizationScript.replacingOccurrences(
            of: " with administrator privileges", with: "",
        )
        let arguments = [AuthorizedCLIInstaller.linkCommand(source: source, destination: destination)]
        let installed = try await AppleScriptClient.live.execute(script, "installcli", arguments)
        #expect(installed == "installed")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path) == source.path)
        let conflict = try await AppleScriptClient.live.execute(script, "installcli", arguments)
        #expect(conflict == "conflict")
    }
}

private actor RecordingAppleScriptRunner {
    struct Invocation: Sendable {
        let source: String
        let handler: String
        let arguments: [String]
    }

    let output: String
    var invocation: Invocation?

    init(output: String) {
        self.output = output
    }

    func execute(source: String, handler: String, arguments: [String]) async throws -> String {
        invocation = Invocation(source: source, handler: handler, arguments: arguments)
        return output
    }
}
