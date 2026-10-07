import Foundation
@testable import MoyKit
import Testing

struct ExecutableValidationTests {
    @Test(arguments: ["command", "relative", "missing", "broken-link"])
    func `rejects unavailable executables without writing JSON`(kind: String) async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let repository = repository(fixture.paths)
        let missing = fixture.root.appending(path: "missing-tool")
        let brokenLink = fixture.root.appending(path: "broken-link")
        try FileManager.default.createSymbolicLink(at: brokenLink, withDestinationURL: missing)
        let path: String = switch kind {
        case "command": "unknown-command"
        case "relative": "./unknown-command"
        case "broken-link": brokenLink.path
        default: missing.path
        }
        let draft = try ServiceDraft(identifier: ServiceIdentifier("invalid-tool"), programArguments: [path])

        await #expect(throws: MoyError.executableNotFound(path)) {
            _ = try await repository.create(draft)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.servicesFile.path))
        #expect(try await repository.list().isEmpty)
    }

    @Test(arguments: [false, true])
    func `rejects files without execute permission and directories`(directory: Bool) async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let repository = repository(fixture.paths)
        let tool = fixture.root.appending(path: "tool")
        if directory {
            try FileManager.default.createDirectory(at: tool, withIntermediateDirectories: true)
        } else {
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tool.path)
        }
        let draft = try ServiceDraft(identifier: ServiceIdentifier("invalid-tool"), programArguments: [tool.path])

        await #expect(throws: MoyError.executableNotRunnable(tool.path)) {
            _ = try await repository.create(draft)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.servicesFile.path))
    }

    @Test
    func `symlinks are accepted and deleted executables remain readable and repairable`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let repository = repository(fixture.paths)
        let tool = fixture.root.appending(path: "実行ファイル tool")
        let link = fixture.root.appending(path: "tool-link")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tool)
        let identifier = try ServiceIdentifier("valid-tool")
        let created = try await repository.create(ServiceDraft(
            identifier: identifier, programArguments: [link.path],
        ))
        let savedJSON = try Data(contentsOf: fixture.paths.servicesFile)

        try FileManager.default.removeItem(at: tool)
        #expect(try await repository.find(identifier: identifier) == created)
        #expect(try await repository.list() == [created])
        await #expect(throws: MoyError.executableNotFound(link.path)) {
            try await repository.update(created)
        }
        #expect(try Data(contentsOf: fixture.paths.servicesFile) == savedJSON)

        var repaired = created
        repaired.programArguments = ["/usr/bin/true"]
        try await repository.update(repaired)
        #expect(try await repository.find(identifier: identifier) == repaired)

        try FileManager.default.removeItem(at: link)
        try await repository.remove(identifier: identifier)
        #expect(try await repository.list().isEmpty)
    }

    private func repository(_ paths: MoyPaths) -> JSONServiceRepository {
        JSONServiceRepository(paths: paths, labelChecker: UnloadedExecutableLabelChecker())
    }
}

private struct UnloadedExecutableLabelChecker: ServiceLabelChecking {
    func isLoaded(label _: String) async throws -> Bool {
        false
    }
}
