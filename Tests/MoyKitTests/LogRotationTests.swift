import Darwin
import Foundation
@testable import MoyKit
import Testing

@Suite("Log rotation")
struct LogRotationTests {
    @Test
    func `copytruncate preserves inode permissions and open writer`() throws {
        let fixture = try RotationFixture()
        defer { fixture.remove() }
        let file = fixture.paths.logDirectory.appending(path: "service.log")
        let contents = Data(repeating: 65, count: 1_000_001)
        try contents.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let writer = open(file.path, O_WRONLY | O_APPEND)
        #expect(writer >= 0)
        defer { close(writer) }
        var before = stat()
        #expect(fstat(writer, &before) == 0)
        try fixture.repository.save(.init(isEnabled: true, maximumSizeMB: 1, generations: 2))
        try fixture.repository.rotate()
        #expect(try Data(contentsOf: file).isEmpty)
        #expect(try Data(contentsOf: URL(filePath: file.path + ".1")) == contents)
        var after = stat()
        #expect(fstat(writer, &after) == 0)
        #expect(before.st_ino == after.st_ino)
        #expect(before.st_uid == after.st_uid)
        #expect(before.st_mode == after.st_mode)
        #expect(write(writer, "next\n", 5) == 5)
        #expect(try String(contentsOf: file, encoding: .utf8) == "next\n")
    }

    @Test
    func `generations retain newest archives and prune after count decreases`() throws {
        let fixture = try RotationFixture()
        defer { fixture.remove() }
        let file = fixture.paths.logDirectory.appending(path: "service.log")
        try fixture.repository.save(.init(isEnabled: true, maximumSizeMB: 1, generations: 3))
        for value: UInt8 in [65, 66, 67, 68] {
            try Data(repeating: value, count: 1_000_000).write(to: file)
            try fixture.repository.rotate()
        }
        #expect(try Data(contentsOf: URL(filePath: file.path + ".1")).first == 68)
        #expect(try Data(contentsOf: URL(filePath: file.path + ".3")).first == 66)
        #expect(!FileManager.default.fileExists(atPath: file.path + ".4"))
        try fixture.repository.save(.init(isEnabled: true, maximumSizeMB: 1, generations: 1))
        try Data(repeating: 69, count: 1_000_000).write(to: file)
        try fixture.repository.rotate()
        #expect(!FileManager.default.fileExists(atPath: file.path + ".2"))
        #expect(!FileManager.default.fileExists(atPath: file.path + ".3"))
    }

    @Test
    func `disabled small numbered nested and linked files are untouched`() throws {
        let fixture = try RotationFixture()
        defer { fixture.remove() }
        let manager = FileManager.default
        let large = fixture.paths.logDirectory.appending(path: "orphan.log")
        let data = Data(repeating: 65, count: 1_000_000)
        try data.write(to: large)
        try fixture.repository.rotate()
        #expect(try Data(contentsOf: large) == data)
        let numbered = fixture.paths.logDirectory.appending(path: "other.log.1")
        try data.write(to: numbered)
        let nested = fixture.paths.logDirectory.appending(path: "nested")
        try manager.createDirectory(at: nested, withIntermediateDirectories: true)
        let nestedLog = nested.appending(path: "nested.log")
        try data.write(to: nestedLog)
        let outside = fixture.root.appending(path: "outside.log")
        try data.write(to: outside)
        try manager.createSymbolicLink(atPath: fixture.paths.logDirectory.appending(path: "link.log").path,
                                       withDestinationPath: outside.path)
        let small = fixture.paths.logDirectory.appending(path: "small.log")
        try Data("small".utf8).write(to: small)
        try fixture.repository.save(.init(isEnabled: true, maximumSizeMB: 1))
        try fixture.repository.rotate()
        #expect(try Data(contentsOf: large).isEmpty)
        for file in [numbered, nestedLog, outside] {
            #expect(try Data(contentsOf: file) == data)
        }
        #expect(try Data(contentsOf: small) == Data("small".utf8))
    }

    @Test
    func `archive failure preserves original and continues with other logs`() throws {
        let fixture = try RotationFixture()
        defer { fixture.remove() }
        let manager = FileManager.default
        let bad = fixture.paths.logDirectory.appending(path: "bad.log")
        let good = fixture.paths.logDirectory.appending(path: "good.log")
        let data = Data(repeating: 65, count: 1_000_000)
        try data.write(to: bad)
        try data.write(to: good)
        try manager.createSymbolicLink(atPath: bad.path + ".1", withDestinationPath: good.path)
        try fixture.repository.save(.init(isEnabled: true, maximumSizeMB: 1))
        #expect(throws: LogRotationError.self) { try fixture.repository.rotate() }
        #expect(try Data(contentsOf: bad) == data)
        #expect(try Data(contentsOf: good).isEmpty)
        #expect(try fixture.repository.failures().count == 1)
        let entries = try manager.contentsOfDirectory(atPath: fixture.paths.logDirectory.path)
        #expect(!entries.contains { $0.hasSuffix(".tmp") })
    }

    @Test
    func `invalid or corrupt settings never replace configuration`() throws {
        let fixture = try RotationFixture()
        defer { fixture.remove() }
        try fixture.repository.save(.init(isEnabled: true))
        #expect(throws: LogRotationError.invalidSettings) {
            try fixture.repository.save(.init(maximumSizeMB: 0))
        }
        #expect(try fixture.repository.settings().isEnabled)
        try Data("broken".utf8).write(to: fixture.paths.dataDirectory.appending(path: "log-rotation.json"))
        #expect(throws: (any Error).self) { try fixture.repository.rotate() }
    }

    @Test
    func `concurrent rotations serialize and do not create duplicate archives`() async throws {
        let fixture = try RotationFixture()
        defer { fixture.remove() }
        let file = fixture.paths.logDirectory.appending(path: "service.log")
        try Data(repeating: 65, count: 1_000_000).write(to: file)
        try fixture.repository.save(.init(isEnabled: true, maximumSizeMB: 1))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 2 {
                group.addTask { try fixture.repository.rotate() }
            }
            try await group.waitForAll()
        }
        #expect(try Data(contentsOf: file).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path + ".2"))
    }

    @Test
    func `conflicting internal plist is preserved and disabled state is restored`() async throws {
        let fixture = try RotationFixture()
        defer { fixture.remove() }
        let manager = FileManager.default
        try manager.createDirectory(at: fixture.paths.launchAgentsDirectory, withIntermediateDirectories: true)
        let job = fixture.paths.launchAgentsDirectory.appending(path: DefaultLogRotationUseCase.label + ".plist")
        let data = try PropertyListSerialization.data(fromPropertyList: ["Label": "other"], format: .xml, options: 0)
        try data.write(to: job)
        let useCase = DefaultLogRotationUseCase(executable: "/missing", paths: fixture.paths,
                                                runner: RotationProcessRunner())
        await #expect(throws: LogRotationError.self) { try await useCase.update(.init(isEnabled: true)) }
        #expect(try !fixture.repository.settings().isEnabled)
        #expect(try Data(contentsOf: job) == data)
    }

    @Test(arguments: [true, false])
    func `failed registration changes restore observed state and can retry`(enabled: Bool) async throws {
        let fixture = try RotationFixture()
        defer { fixture.remove() }
        let executable = try fixture.makeExecutable()
        let runner = RotationProcessRunner()
        let useCase = DefaultLogRotationUseCase(executable: executable.path, paths: fixture.paths, runner: runner)
        if !enabled {
            _ = try await useCase.update(.init(isEnabled: true))
        }
        await runner.fail(enabled ? "bootstrap" : "bootout")
        do {
            _ = try await useCase.update(.init(isEnabled: enabled, maximumSizeMB: 25, generations: 8))
            Issue.record("Expected registration failure")
        } catch let LogRotationError.jobUpdateFailed(actual, _) {
            #expect(actual.isEnabled == !enabled)
            #expect(actual.maximumSizeMB == 25)
            #expect(actual.generations == 8)
            #expect(try fixture.repository.settings() == actual)
        }
        await runner.fail(nil)
        // Opening Settings must preserve the observed state rather than retrying the failed request.
        #expect(try await useCase.refresh().settings.isEnabled == !enabled)
        #expect(await runner.loaded == !enabled)
        #expect(try await useCase.update(.init(isEnabled: enabled)).settings.isEnabled == enabled)
    }

    @Test
    func `failure after launchd changed uses observed state instead of previous state`() async throws {
        let fixture = try RotationFixture()
        defer { fixture.remove() }
        let runner = RotationProcessRunner()
        let executable = try fixture.makeExecutable()
        let useCase = DefaultLogRotationUseCase(executable: executable.path, paths: fixture.paths, runner: runner)
        _ = try await useCase.update(.init(isEnabled: true))
        await runner.fail("bootout", changesState: true)
        do {
            _ = try await useCase.update(.init(isEnabled: false))
            Issue.record("Expected bootout error")
        } catch let LogRotationError.jobUpdateFailed(actual, _) {
            #expect(!actual.isEnabled)
            #expect(try !fixture.repository.settings().isEnabled)
        }
    }

    @Test
    func `unavailable launchd status is reported without assuming disabled`() async throws {
        let fixture = try RotationFixture()
        defer { fixture.remove() }
        let runner = RotationProcessRunner()
        let useCase = DefaultLogRotationUseCase(executable: "/missing", paths: fixture.paths, runner: runner)
        await runner.fail("print")
        do {
            _ = try await useCase.update(.init(isEnabled: true))
            Issue.record("Expected unknown status")
        } catch let LogRotationError.jobStateUnavailable(reason) {
            #expect(!reason.isEmpty)
            #expect(try fixture.repository.settings().isEnabled)
        }
    }

    @Test
    func `job registration refresh relocation and disabling use dedicated label`() async throws {
        let fixture = try RotationFixture()
        defer { fixture.remove() }
        let runner = RotationProcessRunner()
        let executable = fixture.root.appending(path: "Moy.app/Contents/Helpers/moy")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(), withIntermediateDirectories: true,
        )
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let useCase = DefaultLogRotationUseCase(executable: executable.path, paths: fixture.paths, runner: runner)
        #expect(try await useCase.refresh().settings == .init())
        _ = try await useCase.update(.init(isEnabled: true))
        #expect(await runner.bootstrapCount == 1)
        _ = try await useCase.refresh()
        #expect(await runner.bootstrapCount == 1)
        let job = fixture.paths.launchAgentsDirectory.appending(path: DefaultLogRotationUseCase.label + ".plist")
        let dictionary = try #require(
            PropertyListSerialization.propertyList(from: Data(contentsOf: job), format: nil) as? [String: Any],
        )
        #expect(dictionary["StartInterval"] as? Int == 3600)
        #expect(dictionary["RunAtLoad"] as? Bool == true)
        #expect(dictionary["KeepAlive"] == nil)
        #expect(dictionary["ProgramArguments"] as? [String] == [executable.path, "internal-rotate-logs"])
        #expect(!ServiceIdentifier.isValid("internal.log-rotation"))
        let moved = fixture.root.appending(path: "Moved Moy.app/Contents/Helpers/moy")
        try FileManager.default.createDirectory(
            at: moved.deletingLastPathComponent(), withIntermediateDirectories: true,
        )
        try FileManager.default.copyItem(at: executable, to: moved)
        let relocated = DefaultLogRotationUseCase(executable: moved.path, paths: fixture.paths, runner: runner)
        _ = try await relocated.refresh()
        #expect(await runner.bootstrapCount == 2)
        #expect(await runner.bootoutCount == 1)
        _ = try await relocated.update(.init(isEnabled: false))
        #expect(await runner.bootoutCount == 2)
        #expect(!FileManager.default.fileExists(atPath: job.path))
        #expect(try !fixture.repository.settings().isEnabled)
    }
}

private struct RotationFixture {
    let root: URL
    let paths: MoyPaths
    var repository: LocalLogRotationRepository {
        .init(paths: paths)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        paths = MoyPaths(dataDirectory: root.appending(path: "data"),
                         launchAgentsDirectory: root.appending(path: "agents"),
                         logDirectory: root.appending(path: "logs"))
        try FileManager.default.createDirectory(at: paths.logDirectory, withIntermediateDirectories: true)
    }

    func makeExecutable() throws -> URL {
        let executable = root.appending(path: "Moy.app/Contents/Helpers/moy")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(), withIntermediateDirectories: true,
        )
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return executable
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor RotationProcessRunner: ProcessRunning {
    var failureCommand: String?
    var changesStateOnFailure = false
    var loaded = false
    var bootstrapCount = 0
    var bootoutCount = 0

    func fail(_ command: String?, changesState: Bool = false) {
        failureCommand = command
        changesStateOnFailure = changesState
    }

    func run(executable _: String, arguments: [String]) async throws -> ProcessResult {
        if let failureCommand, arguments.first == failureCommand {
            if changesStateOnFailure {
                loaded = failureCommand == "bootstrap"
            }
            return .init(status: 5, output: "Injected failure")
        }
        switch arguments.first {
        case "print": return .init(status: loaded ? 0 : 113, output: "")
        case "bootstrap": loaded = true; bootstrapCount += 1
        case "bootout": loaded = false; bootoutCount += 1
        default: Issue.record("Unexpected launchctl call")
        }
        return .init(status: 0, output: "")
    }
}
