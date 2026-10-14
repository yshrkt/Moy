import Foundation
@testable import MoyApp
import MoyKit
import Testing

struct BundledCLITests {
    @Test
    func `daemon authorization invokes the embedded CLI instead of the app executable`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoyBundledCLITests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appending(path: "Moy.app")
        let gui = app.appending(path: "Contents/MacOS/Moy")
        let cli = app.appending(path: "Contents/Helpers/moy")
        try installScript("#!/bin/sh\nexit 77\n", at: gui)
        try installScript("#!/bin/sh\nprintf '%s' '{\"error\":null}'\n", at: cli)
        let info: [String: Any] = [
            "CFBundleExecutable": "Moy", "CFBundleIdentifier": "com.sputnik-apps.moy-path-test",
            "CFBundlePackageType": "APPL",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appending(path: "Contents/Info.plist"))
        let bundle = try #require(Bundle(url: app))
        let executable = BundledCLI.executableURL(in: bundle)
        #expect(executable == cli)
        let service = try ServiceDefinition(
            identifier: ServiceIdentifier("bundled-cli-test"), kind: .launchDaemon,
            programArguments: ["/usr/bin/true"], standardOutPath: "/tmp/path-test.out",
            standardErrorPath: "/tmp/path-test.err",
        )
        let useCase = AuthorizedServiceManagementUseCase(
            base: TestServiceManagementUseCase(services: [service]),
            authorization: .init(execute: { command in
                // Exercise the actual command and shell quoting without asking for administrator privileges.
                let result = try await DefaultProcessRunner().run(executable: "/bin/sh", arguments: ["-c", command])
                #expect(result.status == 0, "The GUI executable must never be invoked")
                return result.output
            }),
            executable: executable,
        )
        try await useCase.enable(identifier: service.identifier)
    }

    @Test
    func `missing embedded CLI fails before requesting administrator privileges`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoyMissingCLITests-\(UUID())")
        let service = try ServiceDefinition(
            identifier: ServiceIdentifier("missing-cli-test"), kind: .launchDaemon,
            programArguments: ["/usr/bin/true"], standardOutPath: "/tmp/path-test.out",
            standardErrorPath: "/tmp/path-test.err",
        )
        let useCase = AuthorizedServiceManagementUseCase(
            base: TestServiceManagementUseCase(services: [service]),
            authorization: .init(execute: { _ in
                Issue.record("Authentication must not be requested without the embedded CLI")
                return "{}"
            }),
            executable: root.appending(path: "Contents/Helpers/moy"),
        )
        await #expect(throws: MoyError.operationFailed("Bundled CLI executable not found")) {
            try await useCase.enable(identifier: service.identifier)
        }
    }

    private func installScript(_ content: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
