import Foundation
@testable import MoyKit
import Testing

struct ServiceUpdateTests {
    @Test(arguments: UpdateStep.allCases)
    func `failed application retains saved definition and never restores old state`(step: UpdateStep) async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let repository = JSONServiceRepository(paths: fixture.paths, labelChecker: UpdateLabelChecker())
        let oldExecutable = fixture.root.appending(path: "old-executable")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: oldExecutable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: oldExecutable.path)
        var service = try await repository.create(ServiceDraft(
            identifier: ServiceIdentifier("update-test"),
            programArguments: [oldExecutable.path],
        ))
        try FileManager.default.removeItem(at: oldExecutable)
        service.programArguments = ["/usr/bin/true"]
        let launch = UpdateLaunchRepository(failureStep: step)
        let useCase = DefaultServiceManagementUseCase(serviceRepository: repository, launchAgentRepository: launch)

        await #expect(throws: MoyError.serviceUpdateNotApplied(
            identifier: service.identifier.rawValue,
            reason: UpdateLaunchRepository.failure.localizedDescription,
        )) { try await useCase.update(service) }

        #expect(try await repository.find(identifier: service.identifier) == service)
        let failedIndex = try #require(UpdateStep.allCases.firstIndex(of: step))
        let expected = Array(UpdateStep.allCases.prefix(through: failedIndex))
        #expect(await launch.calls == expected)
    }

    @Test(arguments: [false, true])
    func `metadata and invalid saves do not call launchd`(invalid: Bool) async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let repository = JSONServiceRepository(paths: fixture.paths, labelChecker: UpdateLabelChecker())
        let saved = try await repository.create(ServiceDraft(
            identifier: ServiceIdentifier("update-test"), programArguments: ["/usr/bin/true"],
        ))
        var service = saved
        service.displayName = "Updated name"
        let launch = UpdateLaunchRepository(failureStep: .status)
        let useCase = DefaultServiceManagementUseCase(serviceRepository: repository, launchAgentRepository: launch)
        if invalid {
            service.programArguments = ["/missing-executable"]
            await #expect(throws: MoyError.executableNotFound("/missing-executable")) {
                try await useCase.update(service)
            }
            #expect(try await repository.find(identifier: service.identifier) == saved)
        } else {
            try await useCase.update(service)
            #expect(try await repository.find(identifier: service.identifier) == service)
        }
        #expect(await launch.calls.isEmpty)
    }
}

enum UpdateStep: CaseIterable, Sendable {
    case status
    case disable
    case enable
    case restart
}

private struct UpdateLabelChecker: ServiceLabelChecking {
    func isLoaded(label _: String) async throws -> Bool {
        false
    }
}

private actor UpdateLaunchRepository: LaunchdRepository {
    static let failure = MoyError.launchctlFailed(arguments: ["test"], status: 5, message: "forced failure")
    let failureStep: UpdateStep
    private(set) var calls: [UpdateStep] = []

    init(failureStep: UpdateStep) {
        self.failureStep = failureStep
    }

    func status(identifier: ServiceIdentifier) async throws -> ServiceStatus {
        try record(.status)
        return ServiceStatus(identifier: identifier, registration: .enabled, runtime: .running(pid: 42))
    }

    func disable(identifier _: ServiceIdentifier) async throws {
        try record(.disable)
    }

    func enable(_: ServiceDefinition) async throws {
        try record(.enable)
    }

    func restart(identifier _: ServiceIdentifier) async throws {
        try record(.restart)
    }

    private func record(_ step: UpdateStep) throws {
        calls.append(step)
        if step == failureStep {
            throw Self.failure
        }
    }
}
