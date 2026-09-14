import Foundation
@testable import MoyKit
import Testing

struct JSONServiceRepositoryTests {
    @Test
    func `creates reads updates and removes service`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let repository = JSONServiceRepository(
            paths: fixture.paths,
            labelChecker: StubLabelChecker(isLoaded: false),
        )

        let identifier = try ServiceIdentifier("true-service")
        let created = try await repository.create(
            ServiceDraft(identifier: identifier, programArguments: ["/usr/bin/true"]),
        )
        #expect(created.identifier == identifier)
        #expect(created.standardOutPath.hasSuffix("com.sputnik-apps.moy.true-service.stdout.log"))
        #expect(created.name == "true-service")
        #expect(try await repository.list() == [created])

        var updated = created
        updated.displayName = "Updated"
        try await repository.update(updated)
        #expect(try await repository.find(identifier: identifier).displayName == "Updated")

        try await repository.remove(identifier: identifier)
        #expect(try await repository.list().isEmpty)
    }

    @Test
    func `rejects a label already loaded by launchd`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let repository = JSONServiceRepository(
            paths: fixture.paths,
            labelChecker: StubLabelChecker(isLoaded: true),
        )
        let identifier = try ServiceIdentifier("true-service")

        await #expect(throws: MoyError.self) {
            _ = try await repository.create(
                ServiceDraft(identifier: identifier, programArguments: ["/usr/bin/true"]),
            )
        }
    }

    @Test
    func `corrupt JSON is never treated as an empty store`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.paths.dataDirectory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fixture.paths.servicesFile)
        let repository = JSONServiceRepository(paths: fixture.paths)

        await #expect(throws: MoyError.self) {
            _ = try await repository.list()
        }
        let storedData = try Data(contentsOf: fixture.paths.servicesFile)
        #expect(String(data: storedData, encoding: .utf8) == "not json")
    }
}

private struct StubLabelChecker: ServiceLabelChecking {
    let isLoaded: Bool

    func isLoaded(label _: String) async throws -> Bool {
        isLoaded
    }
}

struct TemporaryPaths {
    let root: URL
    let paths: MoyPaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "MoyTests-\(UUID().uuidString)")
        paths = MoyPaths(
            dataDirectory: root.appending(path: "data"),
            launchAgentsDirectory: root.appending(path: "agents"),
            logDirectory: root.appending(path: "logs"),
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
