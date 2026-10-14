import Foundation
@testable import MoyKit
import Testing

struct UserServiceRepositoryTests {
    @Test
    func `daemon log preparation delegates the paths to the original user`() async throws {
        let runner = UserRepositoryProcessStub(response: .init())
        let repository = UserServiceRepository(userID: 501, executable: "/test/moy", runner: runner)
        let service = try ServiceDefinition(
            identifier: ServiceIdentifier("remote-log"), kind: .launchDaemon, programArguments: ["/usr/bin/true"],
            standardOutPath: "/Users/example/Library/Logs/Moy/stdout.log",
            standardErrorPath: "/Users/example/Library/Logs/Moy/stderr.log",
        )
        try await repository.prepare(for: service)
        let invocation = try #require(await runner.invocation)
        #expect(invocation.arguments[2] == "#501")
        let payload = try #require(invocation.arguments.last.flatMap { Data(base64Encoded: $0) })
        let request = try JSONDecoder().decode(UserRepositoryRequest.self, from: payload)
        if case let .prepareLogs(received) = request {
            #expect(received == service)
        } else {
            Issue.record("Expected a log preparation request")
        }
    }

    @Test
    func `user file operations run through an unprivileged subprocess with a clean environment`() async throws {
        var response = UserRepositoryResponse()
        response.services = []
        let runner = UserRepositoryProcessStub(response: response)
        let repository = UserServiceRepository(userID: 501, executable: "/Applications/Moy.app/Contents/Helpers/moy",
                                               runner: runner)
        #expect(try await repository.list().isEmpty)
        let invocation = try #require(await runner.invocation)
        #expect(invocation.executable == "/usr/bin/sudo")
        #expect(invocation.arguments.prefix(8) == ["-H", "-u", "#501", "--", "/usr/bin/env", "-i",
                                                   "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
                                                   "/Applications/Moy.app/Contents/Helpers/moy"])
        #expect(invocation.arguments[8] == "internal-repository")
    }

    @Test
    func `typed storage failures survive the subprocess boundary`() async throws {
        var response = UserRepositoryResponse()
        response.error = .serviceChanged
        let repository = UserServiceRepository(userID: 501, executable: "/test/moy",
                                               runner: UserRepositoryProcessStub(response: response))
        await #expect(throws: MoyError.serviceChanged) { try await repository.list() }
    }

    @Test
    func `missing response never becomes an empty store`() async throws {
        let repository = UserServiceRepository(userID: 501, executable: "/test/moy",
                                               runner: UserRepositoryProcessStub(response: .init()))
        await #expect(throws: MoyError.self) { try await repository.list() }
    }

    @Test
    func `reviewed definitions reject changes before elevated operations`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let base = JSONServiceRepository(paths: fixture.paths, labelChecker: UserRepositoryLabelStub())
        let original = try await base.create(ServiceDraft(
            identifier: ServiceIdentifier("reviewed"), kind: .launchDaemon, programArguments: ["/usr/bin/true"],
        ))
        let reviewed = ReviewedServiceRepository(base: base, expected: original)
        #expect(try await reviewed.find(identifier: original.identifier) == original)
        var changed = original
        changed.programArguments = ["/usr/bin/false"]
        try await base.update(changed)
        await #expect(throws: MoyError.serviceChanged) { try await reviewed.find(identifier: original.identifier) }
        await #expect(throws: MoyError.serviceChanged) { try await reviewed.update(original) }
        #expect(try await base.find(identifier: original.identifier) == changed)
    }
}

private actor UserRepositoryProcessStub: ProcessRunning {
    struct Invocation: Sendable {
        let executable: String
        let arguments: [String]
    }

    let response: UserRepositoryResponse
    var invocation: Invocation?
    init(response: UserRepositoryResponse) {
        self.response = response
    }

    func run(executable: String, arguments: [String]) async throws -> ProcessResult {
        invocation = .init(executable: executable, arguments: arguments)
        let data = try JSONEncoder().encode(response)
        return try .init(status: 0, output: #require(String(data: data, encoding: .utf8)))
    }
}

private struct UserRepositoryLabelStub: ServiceLabelChecking {
    func isLoaded(label _: String) async throws -> Bool {
        false
    }
}
