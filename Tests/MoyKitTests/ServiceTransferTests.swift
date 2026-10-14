import Foundation
@testable import MoyKit
import Testing

struct ServiceTransferTests {
    @Test(arguments: [false, true])
    func `import preserves settings and enables only when requested`(enable: Bool) async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let launch = TransferLaunchRepository()
        let management = makeManagement(paths: fixture.paths, launch: launch)
        let transfer = DefaultServiceTransferUseCase(serviceManagementUseCase: management, paths: fixture.paths)
        var service = try fixtureService()
        service.programArguments = ["/usr/bin/printf", "", "hello world", "'quoted'", "$PORT"]
        service.standardOutPath = ""
        let url = fixture.root.appending(path: "service.json")
        try await JSONServiceDocumentRepository().write(ServiceJSONDocument(service: service), to: url)
        let created = try await transfer.importService(from: url, enable: enable)
        service.standardOutPath = fixture.paths.standardOutFile(identifier: service.identifier).path
        #expect(created == service)
        #expect(try await management.find(identifier: service.identifier) == service)
        #expect(await launch.enabled.count == (enable ? 1 : 0))
        await #expect(throws: MoyError.duplicateService(service.identifier.rawValue)) {
            _ = try await transfer.importService(from: url)
        }
        #expect(try await management.list() == [created])
    }

    @Test
    func `exported default logs are regenerated in a different environment`() async throws {
        let source = try TemporaryPaths()
        defer { source.remove() }
        let destination = try TemporaryPaths()
        defer { destination.remove() }
        let sourceManagement = makeManagement(paths: source.paths, launch: TransferLaunchRepository())
        let identifier = try ServiceIdentifier("portable-service")
        _ = try await sourceManagement.create(ServiceDraft(
            identifier: identifier, programArguments: ["/usr/bin/true"],
        ))
        let url = source.root.appending(path: "service.json")
        try await DefaultServiceTransferUseCase(serviceManagementUseCase: sourceManagement, paths: source.paths)
            .exportService(identifier: identifier, to: url)
        let document = try await JSONServiceDocumentRepository().read(from: url)
        #expect(document.service.standardOutPath.isEmpty)
        #expect(document.service.standardErrorPath.isEmpty)
        let targetManagement = makeManagement(paths: destination.paths, launch: TransferLaunchRepository())
        let imported = try await DefaultServiceTransferUseCase(
            serviceManagementUseCase: targetManagement, paths: destination.paths,
        ).importService(from: url)
        #expect(imported.standardOutPath == destination.paths.standardOutFile(identifier: identifier).path)
        #expect(imported.standardErrorPath == destination.paths.standardErrorFile(identifier: identifier).path)
    }

    @Test
    func `read does not register or check executable existence but import does`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let management = makeManagement(paths: fixture.paths, launch: TransferLaunchRepository())
        let transfer = DefaultServiceTransferUseCase(serviceManagementUseCase: management, paths: fixture.paths)
        var service = try fixtureService()
        service.programArguments = [fixture.root.appending(path: "missing-tool").path]
        let url = fixture.root.appending(path: "service.json")
        try await JSONServiceDocumentRepository().write(ServiceJSONDocument(service: service), to: url)
        #expect(try await transfer.readService(from: url).programArguments == service.programArguments)
        #expect(try await management.list().isEmpty)
        await #expect(throws: MoyError.executableNotFound(service.programArguments[0])) {
            _ = try await transfer.importService(from: url)
        }
        #expect(try await management.list().isEmpty)
    }

    @Test
    func `export works after executable removal and find failures preserve output`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let executable = fixture.root.appending(path: "tool")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let management = makeManagement(paths: fixture.paths, launch: TransferLaunchRepository())
        let created = try await management.create(ServiceDraft(
            identifier: ServiceIdentifier("removed-tool"), programArguments: [executable.path],
        ))
        try FileManager.default.removeItem(at: executable)
        let transfer = DefaultServiceTransferUseCase(serviceManagementUseCase: management, paths: fixture.paths)
        let url = fixture.root.appending(path: "service.json")
        try await transfer.exportService(identifier: created.identifier, to: url)
        #expect(try await JSONServiceDocumentRepository().read(from: url).service.programArguments == [executable.path])
        let previous = try Data(contentsOf: url)
        await #expect(throws: MoyError.serviceNotFound("unknown")) {
            try await transfer.exportService(identifier: ServiceIdentifier("unknown"), to: url)
        }
        #expect(try Data(contentsOf: url) == previous)
    }

    @Test
    func `failed enable follows existing registration rollback behavior`() async throws {
        let fixture = try TemporaryPaths()
        defer { fixture.remove() }
        let management = makeManagement(paths: fixture.paths, launch: TransferLaunchRepository(failEnable: true))
        let url = fixture.root.appending(path: "service.json")
        try await JSONServiceDocumentRepository().write(ServiceJSONDocument(service: fixtureService()), to: url)
        await #expect(throws: MoyError.self) {
            _ = try await DefaultServiceTransferUseCase(serviceManagementUseCase: management, paths: fixture.paths)
                .importService(from: url, enable: true)
        }
        #expect(try await management.list().isEmpty)
    }

    private func makeManagement(paths: MoyPaths, launch: TransferLaunchRepository) -> DefaultServiceManagementUseCase {
        DefaultServiceManagementUseCase(
            serviceRepository: JSONServiceRepository(paths: paths, labelChecker: TransferLabelChecker()),
            launchAgentRepository: launch,
        )
    }
}

private struct TransferLabelChecker: ServiceLabelChecking {
    func isLoaded(label _: String) async throws -> Bool {
        false
    }
}

private actor TransferLaunchRepository: LaunchdRepository {
    private let failEnable: Bool
    private(set) var enabled: [ServiceDefinition] = []

    init(failEnable: Bool = false) {
        self.failEnable = failEnable
    }

    func enable(_ service: ServiceDefinition) async throws {
        if failEnable {
            throw MoyError.launchctlFailed(arguments: ["bootstrap"], status: 1, message: "test failure")
        }
        enabled.append(service)
    }

    func status(identifier: ServiceIdentifier) async throws -> ServiceStatus {
        ServiceStatus(identifier: identifier, registration: .disabled, runtime: .notLoaded)
    }

    func disable(identifier _: ServiceIdentifier) async throws {}
    func restart(identifier _: ServiceIdentifier) async throws {}
}
