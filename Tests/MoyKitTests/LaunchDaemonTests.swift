import Darwin
import Foundation
@testable import MoyKit
import Testing

struct LaunchDaemonTests {
    @Test
    func `daemon kind and default logs survive storage and transfer`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let paths = daemonPaths(fixture)
        let repository = JSONServiceRepository(paths: paths, labelChecker: DaemonLabelChecker())
        let identifier = try ServiceIdentifier("daemon-test")
        let service = try await repository.create(ServiceDraft(
            identifier: identifier, kind: .launchDaemon, programArguments: ["/usr/bin/true"],
        ))
        #expect(service.kind == .launchDaemon)
        #expect(service.standardOutPath == paths.standardOutFile(identifier: identifier, kind: .launchDaemon).path)
        #expect(try await repository.find(identifier: identifier) == service)
        let document = fixture.root.appending(path: "daemon.json")
        let management = DefaultServiceManagementUseCase(
            serviceRepository: repository, launchAgentRepository: DaemonLaunchStub(registration: .disabled),
        )
        let transfer = DefaultServiceTransferUseCase(serviceManagementUseCase: management, paths: paths)
        try await transfer.exportService(identifier: identifier, to: document)
        let draft = try await transfer.readService(from: document)
        #expect(draft.kind == .launchDaemon)
        #expect(draft.standardOutPath == nil)
        #expect(draft.standardErrorPath == nil)
        let plist = try PropertyListSerialization.propertyList(
            from: LaunchdPlistWriter().data(for: service), format: nil,
        ) as? [String: Any]
        #expect(plist?["UserName"] as? String == "root")
        #expect(plist?["kind"] == nil)
    }

    @Test(arguments: [ServiceStatus.Registration.disabled, .enabled])
    func `daemon update requires privilege before saving only when registered`(
        registration: ServiceStatus.Registration,
    ) async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let repository = JSONServiceRepository(paths: daemonPaths(fixture), labelChecker: DaemonLabelChecker())
        let original = try await repository.create(ServiceDraft(
            identifier: ServiceIdentifier("privilege-test"), kind: .launchDaemon, programArguments: ["/usr/bin/true"],
        ))
        let agent = DaemonLaunchStub(registration: .disabled)
        let daemon = DaemonLaunchStub(registration: registration)
        let management = DefaultServiceManagementUseCase(
            serviceRepository: repository, launchAgentRepository: agent, launchDaemonRepository: daemon,
            requireAdministrator: { throw MoyError.administratorRequired },
        )
        var changed = original
        changed.runAtLoad = true
        if registration == .enabled {
            await #expect(throws: MoyError.administratorRequired) { try await management.update(changed) }
            #expect(try await repository.find(identifier: original.identifier) == original)
        } else {
            try await management.update(changed)
            #expect(try await repository.find(identifier: original.identifier) == changed)
        }
        #expect(await agent.calls.isEmpty)
        #expect(await daemon.calls == ["status"])
        var metadata = try await repository.find(identifier: original.identifier)
        metadata.displayName = "New name"
        try await management.update(metadata)
        #expect(await daemon.calls == ["status"])
    }

    @Test
    func `daemon create and enable refuses privilege before saving`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let repository = JSONServiceRepository(paths: daemonPaths(fixture), labelChecker: DaemonLabelChecker())
        let launch = DaemonLaunchStub(registration: .disabled)
        let management = DefaultServiceManagementUseCase(
            serviceRepository: repository, launchAgentRepository: launch,
            requireAdministrator: { throw MoyError.administratorRequired },
        )
        await #expect(throws: MoyError.administratorRequired) {
            try await management.create(ServiceDraft(
                identifier: ServiceIdentifier("new-daemon"), kind: .launchDaemon, programArguments: ["/usr/bin/true"],
            ), enable: true)
        }
        #expect(try await repository.list().isEmpty)
        #expect(await launch.calls.isEmpty)
    }

    @Test
    func `kind changes and stale updates do not overwrite definitions`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let repository = JSONServiceRepository(paths: daemonPaths(fixture), labelChecker: DaemonLabelChecker())
        let original = try await repository.create(ServiceDraft(
            identifier: ServiceIdentifier("unchanged-kind"), programArguments: ["/usr/bin/true"],
        ))
        let daemon = ServiceDefinition(
            identifier: original.identifier, kind: .launchDaemon, programArguments: original.programArguments,
            standardOutPath: original.standardOutPath, standardErrorPath: original.standardErrorPath,
        )
        await #expect(throws: MoyError.kindCannotChange) { try await repository.update(daemon) }
        var current = original
        current.description = "Changed elsewhere"
        try await repository.update(current)
        await #expect(throws: MoyError.serviceChanged) { try await repository.update(original, expected: original) }
        #expect(try await repository.find(identifier: original.identifier) == current)
    }

    @Test
    func `daemon status uses the system domain without privilege`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let runner = DaemonProcessStub()
        let repository = LaunchctlServiceRepository(
            paths: daemonPaths(fixture), kind: .launchDaemon, processRunner: runner,
        )
        let identifier = try ServiceIdentifier("system-status")
        let status = try await repository.status(identifier: identifier)
        #expect(status.registration == .disabled)
        #expect(await runner.arguments == [["print", "system/\(identifier.launchdLabel)"]])
        if geteuid() != 0 {
            await #expect(throws: MoyError.administratorRequired) {
                try await repository.restart(identifier: identifier)
            }
            #expect(await runner.arguments.count == 1)
        }
    }

    @Test
    func `sudo resolves the original user and rejects missing or root identities`() throws {
        let user = try MoyUserContext.resolve(effectiveUserID: 0, environment: ["SUDO_UID": String(getuid())])
        #expect(user.userID == getuid())
        #expect(user.homeDirectory.path == FileManager.default.homeDirectoryForCurrentUser.path)
        #expect(throws: MoyError.invalidInvokingUser) {
            try MoyUserContext.resolve(effectiveUserID: 0, environment: [:])
        }
        #expect(throws: MoyError.invalidInvokingUser) {
            try MoyUserContext.resolve(effectiveUserID: 0, environment: ["SUDO_UID": "0"])
        }
    }
}

private func daemonPaths(_ fixture: TemporaryPaths) -> MoyPaths {
    MoyPaths(
        dataDirectory: fixture.paths.dataDirectory, launchAgentsDirectory: fixture.paths.launchAgentsDirectory,
        logDirectory: fixture.paths.logDirectory, launchDaemonsDirectory: fixture.root.appending(path: "daemons"),
        daemonLogDirectory: fixture.root.appending(path: "daemon-logs"),
    )
}

private struct DaemonLabelChecker: ServiceLabelChecking {
    func isLoaded(label _: String) async throws -> Bool {
        false
    }
}

private actor DaemonProcessStub: ProcessRunning {
    var arguments: [[String]] = []
    func run(executable _: String, arguments: [String]) async throws -> ProcessResult {
        self.arguments.append(arguments)
        return .init(status: 113, output: "Could not find service")
    }
}

private actor DaemonLaunchStub: LaunchdRepository {
    var calls: [String] = []
    let registration: ServiceStatus.Registration
    init(registration: ServiceStatus.Registration) {
        self.registration = registration
    }

    func status(identifier: ServiceIdentifier) async throws -> ServiceStatus {
        calls.append("status")
        return .init(identifier: identifier, registration: registration, runtime: .waiting)
    }

    func enable(_: ServiceDefinition) async throws {
        calls.append("enable")
    }

    func disable(identifier _: ServiceIdentifier) async throws {
        calls.append("disable")
    }

    func restart(identifier _: ServiceIdentifier) async throws {
        calls.append("restart")
    }
}
