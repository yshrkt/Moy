import Foundation
@testable import MoyApp
import Testing

@Suite("CLI installer")
struct CLIInstallerTests {
    @Test
    func `install and recognize link after recreating installer`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(try await fixture.installer.status() == .notInstalled)
        try await fixture.installer.install()
        let recreated = CLIInstaller(sourceURL: fixture.source, destinationURL: fixture.destination)
        #expect(try await recreated.status() == .installed)
        try await recreated.install()
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: fixture.destination.path)
        #expect(target == fixture.source.path)
    }

    @Test(arguments: [false, true])
    func `existing file and dangling link are preserved`(danglingLink: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        if danglingLink {
            try FileManager.default.createSymbolicLink(
                atPath: fixture.destination.path,
                withDestinationPath: "/missing-moy-test",
            )
        } else {
            try Data("existing".utf8).write(to: fixture.destination)
        }
        #expect(try await fixture.installer.status() == .conflict)
        await #expect(throws: SettingsFailure.cliDestinationExists) {
            try await fixture.installer.install()
        }
        if danglingLink {
            let target = try FileManager.default.destinationOfSymbolicLink(atPath: fixture.destination.path)
            #expect(target == "/missing-moy-test")
        } else {
            #expect(try String(contentsOf: fixture.destination, encoding: .utf8) == "existing")
        }
    }

    @Test
    func `writable destination does not request authorization`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let installer = CLIInstaller(
            sourceURL: fixture.source,
            destinationURL: fixture.destination,
            authorizationClient: CLIInstallerAuthorizationClient { _, _ in
                Issue.record("A writable destination must not request administrator authentication")
            },
        )
        try await installer.install()
        #expect(try await installer.status() == .installed)
    }

    @Test
    func `permission failure requests authorization and verifies created link`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.root.path)
        let installer = CLIInstaller(
            sourceURL: fixture.source,
            destinationURL: fixture.destination,
            authorizationClient: CLIInstallerAuthorizationClient { source, destination in
                #expect(source == fixture.source)
                #expect(destination == fixture.destination)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.root.path)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                )
                try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: source)
            },
        )
        try await installer.install()
        #expect(try await installer.status() == .installed)
    }

    @Test
    func `authorization result alone is not installation success`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.root.path)
        let installer = CLIInstaller(
            sourceURL: fixture.source,
            destinationURL: fixture.destination,
            authorizationClient: CLIInstallerAuthorizationClient { _, _ in },
        )
        await #expect(throws: SettingsFailure.cliInstallationFailed) {
            try await installer.install()
        }
        #expect(try await installer.status() == .notInstalled)
    }

    @Test
    func `relative link to bundled CLI is recognized`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(
            at: fixture.destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try FileManager.default.createSymbolicLink(
            atPath: fixture.destination.path,
            withDestinationPath: "../bundled-moy",
        )
        #expect(try await fixture.installer.status() == .installed)
    }

    @Test
    func `missing bundled CLI fails without creating link`() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.source)
        await #expect(throws: SettingsFailure.cliNotBundled) {
            try await fixture.installer.install()
        }
        #expect(try await fixture.installer.status() == .notInstalled)
    }

    private struct Fixture {
        let root: URL
        let source: URL
        let destination: URL
        let installer: CLIInstaller

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "moy-cli-test-\(UUID().uuidString)")
            source = root.appending(path: "bundled-moy")
            destination = root.appending(path: "bin/moy")
            installer = CLIInstaller(sourceURL: source, destinationURL: destination)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: source)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        }

        func remove() {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
