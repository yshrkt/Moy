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
    static let success = ProcessResult(status: 0, output: "")
    static let loaded = ProcessResult(status: 0, output: "state = running\npid = 42")
    static let missing = ProcessResult(status: 113, output: "Could not find service")
}
