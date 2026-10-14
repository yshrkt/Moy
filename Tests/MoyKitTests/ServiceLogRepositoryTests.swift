import Darwin
import Foundation
@testable import MoyKit
import Testing

struct ServiceLogRepositoryTests {
    @Test
    func `new daemon logs are user owned and both kinds share the default directory`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let service = try daemon(in: fixture)
        #expect(fixture.paths.standardOutFile(identifier: service.identifier, kind: .launchDaemon)
            == fixture.paths.standardOutFile(identifier: service.identifier))
        #expect(fixture.paths.standardErrorFile(identifier: service.identifier, kind: .launchDaemon)
            == fixture.paths.standardErrorFile(identifier: service.identifier))
        try await LocalServiceLogRepository().prepare(for: service)
        for path in [service.standardOutPath, service.standardErrorPath] {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            #expect(attributes[.ownerAccountID] as? UInt32 == getuid())
            #expect(attributes[.posixPermissions] as? Int == 0o600)
            #expect(try Data(contentsOf: URL(filePath: path)).isEmpty)
        }
    }

    @Test
    func `existing logs retain data ownership and permissions across repeated preparation`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let service = try daemon(in: fixture)
        let repository = LocalServiceLogRepository()
        try await repository.prepare(for: service)
        let url = URL(filePath: service.standardOutPath)
        let previous = Data("existing log\n".utf8)
        try previous.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        let before = try FileManager.default.attributesOfItem(atPath: url.path)
        try await repository.prepare(for: service)
        try await repository.prepare(for: service)
        let after = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(try Data(contentsOf: url) == previous)
        #expect(after[.posixPermissions] as? Int == before[.posixPermissions] as? Int)
        #expect(after[.ownerAccountID] as? UInt32 == before[.ownerAccountID] as? UInt32)
    }

    @Test(arguments: ["readOnly", "directory", "symlink", "fifo", "invalidParent"])
    func `unusable log files fail without modifying existing contents`(kind: String) async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        var service = try daemon(in: fixture)
        let target = fixture.root.appending(path: "target")
        let previous = Data("keep\n".utf8)
        try previous.write(to: target)
        let log = fixture.root.appending(path: "output")
        switch kind {
        case "readOnly":
            try previous.write(to: log)
            try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: log.path)
        case "directory": try FileManager.default.createDirectory(at: log, withIntermediateDirectories: true)
        case "symlink": try FileManager.default.createSymbolicLink(at: log, withDestinationURL: target)
        case "fifo": #expect(mkfifo(log.path, 0o600) == 0)
        case "invalidParent":
            service.standardOutPath = target.appending(path: "output").path
        default: break
        }
        if kind != "invalidParent" {
            service.standardOutPath = log.path
        }
        await #expect(throws: MoyError.self) { try await LocalServiceLogRepository().prepare(for: service) }
        #expect(try Data(contentsOf: target) == previous)
        if kind == "readOnly" {
            #expect(try Data(contentsOf: log) == previous)
        }
    }

    @Test
    func `failed daemon log preparation occurs before plist placement and bootstrap`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let service = try daemon(in: fixture)
        let runner = LogPreparationProcessStub()
        let logs = FailingLogRepository()
        let paths = MoyPaths(
            dataDirectory: fixture.paths.dataDirectory, launchAgentsDirectory: fixture.paths.launchAgentsDirectory,
            logDirectory: fixture.paths.logDirectory, launchDaemonsDirectory: fixture.root.appending(path: "daemons"),
        )
        let repository = LaunchctlServiceRepository(
            paths: paths, kind: .launchDaemon, logRepository: logs,
            fileManager: .default, processRunner: runner, plistWriter: .init(), userID: getuid(),
            unloadVerificationAttempts: 1, unloadVerificationDelay: .zero, checkAdministrator: {},
        )
        await #expect(throws: MoyError.fileOperation(path: service.standardOutPath, reason: "not writable")) {
            try await repository.enable(service)
        }
        #expect(await logs.received == service)
        #expect(await runner.arguments == [["print", "system/\(service.identifier.launchdLabel)"]])
        #expect(!FileManager.default.fileExists(atPath: paths.plistFile(
            identifier: service.identifier, kind: .launchDaemon,
        ).path))
    }

    private func daemon(in fixture: TemporaryPaths) throws -> ServiceDefinition {
        let identifier = try ServiceIdentifier("user-log-test")
        return ServiceDefinition(
            identifier: identifier, kind: .launchDaemon, programArguments: ["/usr/bin/true"],
            standardOutPath: fixture.paths.standardOutFile(identifier: identifier, kind: .launchDaemon).path,
            standardErrorPath: fixture.paths.standardErrorFile(identifier: identifier, kind: .launchDaemon).path,
        )
    }
}

private actor LogPreparationProcessStub: ProcessRunning {
    var arguments: [[String]] = []
    func run(executable _: String, arguments: [String]) async throws -> ProcessResult {
        self.arguments.append(arguments)
        return .init(status: 113, output: "Could not find service")
    }
}

private actor FailingLogRepository: ServiceLogRepository {
    var received: ServiceDefinition?
    func prepare(for service: ServiceDefinition) async throws {
        received = service
        throw MoyError.fileOperation(path: service.standardOutPath, reason: "not writable")
    }
}
