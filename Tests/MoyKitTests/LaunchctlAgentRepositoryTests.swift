import Foundation
@testable import MoyKit
import Testing

struct LaunchctlAgentRepositoryTests {
    @Test
    func `disable waits for launchd to finish unloading before removing plist`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let identifier = try ServiceIdentifier("delayed-bootout")
        try createPlist(for: identifier, in: fixture)
        let runner = ScriptedProcessRunner(results: [
            .loaded,
            .success,
            .loaded,
            .loaded,
            .missing,
        ])
        let repository = makeRepository(paths: fixture.paths, runner: runner, attempts: 3)

        try await repository.disable(identifier: identifier)

        #expect(!FileManager.default.fileExists(atPath: fixture.paths.plistFile(identifier: identifier).path))
        #expect(await runner.receivedArguments().filter { $0.first == "print" }.count == 4)
    }

    @Test
    func `disable preserves plist when launchd stays loaded`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let identifier = try ServiceIdentifier("stuck-bootout")
        try createPlist(for: identifier, in: fixture)
        let runner = ScriptedProcessRunner(results: [
            .loaded,
            .success,
            .loaded,
            .loaded,
        ])
        let repository = makeRepository(paths: fixture.paths, runner: runner, attempts: 2)

        do {
            try await repository.disable(identifier: identifier)
            Issue.record("Expected inconsistent launchd state")
        } catch {
            #expect(error as? MoyError == .inconsistentState(identifier.rawValue))
        }

        #expect(FileManager.default.fileExists(atPath: fixture.paths.plistFile(identifier: identifier).path))
    }
}

extension LaunchctlAgentRepositoryTests {
    @Test(arguments: [ProcessResult.loaded, .failure])
    func `failed enable preserves plist when loaded or status cannot be verified`(
        verification: ProcessResult,
    ) async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let service = try fixtureService()
        let runner = ScriptedProcessRunner(results: [.missing, .failure, verification])
        let repository = makeRepository(paths: fixture.paths, runner: runner, attempts: 1)
        let expected = MoyError.launchctlFailed(
            arguments: ["bootstrap", "gui/501", fixture.paths.plistFile(identifier: service.identifier).path],
            status: ProcessResult.failure.status,
            message: ProcessResult.failure.output,
        )

        await #expect(throws: expected) { try await repository.enable(service) }

        #expect(FileManager.default.fileExists(atPath: fixture.paths.plistFile(identifier: service.identifier).path))
        #expect(await runner.receivedArguments().map { $0[0] } == ["print", "bootstrap", "print"])
    }

    @Test
    func `failed enable removes plist only after confirming service is not loaded`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let service = try fixtureService()
        let runner = ScriptedProcessRunner(results: [.missing, .failure, .missing])
        let repository = makeRepository(paths: fixture.paths, runner: runner, attempts: 1)

        await #expect(throws: MoyError.self) { try await repository.enable(service) }

        #expect(!FileManager.default.fileExists(atPath: fixture.paths.plistFile(identifier: service.identifier).path))
        #expect(await runner.receivedArguments().map { $0[0] } == ["print", "bootstrap", "print"])
    }

    @Test
    func `successful bootstrap with failed verification preserves registration`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let service = try fixtureService()
        let runner = ScriptedProcessRunner(results: [.missing, .success, .failure, .loaded])
        let repository = makeRepository(paths: fixture.paths, runner: runner, attempts: 1)

        await #expect(throws: MoyError.self) { try await repository.enable(service) }

        #expect(FileManager.default.fileExists(atPath: fixture.paths.plistFile(identifier: service.identifier).path))
        #expect(await runner.receivedArguments().contains { $0[0] == "bootout" } == false)
    }

    @Test(arguments: [false, true])
    func `concurrent enable failure does not remove successful registration`(separateRepositories: Bool) async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let service = try fixtureService()
        let runner = ConcurrentEnableRunner()
        let first = LaunchctlAgentRepository(paths: fixture.paths, processRunner: runner, userID: 501)
        let second = separateRepositories
            ? LaunchctlAgentRepository(paths: fixture.paths, processRunner: runner, userID: 501)
            : first

        let successes = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for repository in [first, second] {
                group.addTask {
                    do {
                        try await repository.enable(service)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var count = 0
            for await success in group where success {
                count += 1
            }
            return count
        }

        #expect(successes == 1)
        #expect(await runner.isLoaded)
        #expect(await runner.bootoutCount == 0)
        #expect(FileManager.default.fileExists(atPath: fixture.paths.plistFile(identifier: service.identifier).path))
        #expect(try await first.status(identifier: service.identifier).registration == .enabled)
    }
}

private actor ConcurrentEnableRunner: ProcessRunning {
    private var printCount = 0
    private var initialPrint: CheckedContinuation<ProcessResult, Never>?
    private(set) var isLoaded = false
    private(set) var bootoutCount = 0

    func run(executable _: String, arguments: [String]) async throws -> ProcessResult {
        switch arguments[0] {
        case "print":
            printCount += 1
            if printCount == 1 {
                return await withCheckedContinuation { initialPrint = $0 }
            }
            if printCount == 2 {
                initialPrint?.resume(returning: .missing)
                initialPrint = nil
                return .missing
            }
            return isLoaded ? .loaded : .missing
        case "bootstrap":
            guard !isLoaded else { return .failure }
            isLoaded = true
            return .success
        case "bootout":
            bootoutCount += 1
            isLoaded = false
            return .success
        default:
            throw ScriptedProcessRunnerError.missingResult
        }
    }
}

private extension LaunchctlAgentRepositoryTests {
    func makeRepository(
        paths: MoyPaths,
        runner: ScriptedProcessRunner,
        attempts: Int,
    ) -> LaunchctlAgentRepository {
        LaunchctlAgentRepository(
            paths: paths,
            fileManager: .default,
            processRunner: runner,
            plistWriter: .init(),
            userID: 501,
            unloadVerificationAttempts: attempts,
            unloadVerificationDelay: .zero,
        )
    }

    func createPlist(for identifier: ServiceIdentifier, in fixture: TemporaryPaths) throws {
        try FileManager.default.createDirectory(
            at: fixture.paths.launchAgentsDirectory,
            withIntermediateDirectories: true,
        )
        try Data().write(to: fixture.paths.plistFile(identifier: identifier))
    }
}

private actor ScriptedProcessRunner: ProcessRunning {
    private var results: [ProcessResult]
    private var arguments: [[String]] = []

    init(results: [ProcessResult]) {
        self.results = results
    }

    func run(executable _: String, arguments: [String]) async throws -> ProcessResult {
        self.arguments.append(arguments)
        guard !results.isEmpty else { throw ScriptedProcessRunnerError.missingResult }
        return results.removeFirst()
    }

    func receivedArguments() -> [[String]] {
        arguments
    }
}

private enum ScriptedProcessRunnerError: Error {
    case missingResult
}

private extension ProcessResult {
    static let failure = ProcessResult(status: 5, output: "Input/output error")
    static let success = ProcessResult(status: 0, output: "")
    static let loaded = ProcessResult(status: 0, output: "state = running\npid = 42")
    static let missing = ProcessResult(status: 113, output: "Could not find service")
}
