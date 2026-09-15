@testable import MoyApp
import MoyKit
import NanoRedux
import Testing

@Suite("Services reducer")
struct ServicesReducerTests {
    @Test
    func `create service`() async throws {
        let useCase = TestServiceManagementUseCase()
        let reducer = makeReducer(useCase: useCase)
        var state = ServicesState()

        _ = reducer.reduce(into: &state, action: .presentCreateService)
        _ = reducer.reduce(into: &state, action: .updateEditor(.identifier("api-server")))
        _ = reducer.reduce(into: &state, action: .updateEditor(.displayName("API Server")))
        _ = reducer.reduce(into: &state, action: .updateEditor(.executable("/usr/bin/python3")))
        _ = reducer.reduce(into: &state, action: .addArgument)
        let argumentID = try #require(state.editor?.arguments.first?.id)
        _ = reducer.reduce(into: &state, action: .updateArgument(argumentID, ""))
        _ = reducer.reduce(into: &state, action: .addEnvironmentVariable)
        let variableID = try #require(state.editor?.environmentVariables.first?.id)
        _ = reducer.reduce(into: &state, action: .updateEnvironmentKey(variableID, "MODE"))
        _ = reducer.reduce(into: &state, action: .updateEnvironmentValue(variableID, "development"))

        let effect = reducer.reduce(into: &state, action: .saveService(enable: true))
        #expect(state.isSaving)
        let response = try #require(await effect.execute())
        _ = reducer.reduce(into: &state, action: response)

        let request = try #require(await useCase.lastCreateRequest())
        #expect(request.enable)
        #expect(request.draft.identifier.rawValue == "api-server")
        #expect(request.draft.displayName == "API Server")
        #expect(request.draft.programArguments == ["/usr/bin/python3", ""])
        #expect(request.draft.environmentVariables == ["MODE": "development"])
        #expect(state.editor == nil)
        #expect(state.selectedIdentifier?.rawValue == "api-server")
    }

    @Test
    func `prevent duplicate operation`() async throws {
        let identifier = try ServiceIdentifier("worker")
        let useCase = TestServiceManagementUseCase()
        let reducer = makeReducer(useCase: useCase)
        var state = ServicesState()

        let first = reducer.reduce(into: &state, action: .enableService(identifier))
        let second = reducer.reduce(into: &state, action: .enableService(identifier))
        #expect(state.isOperating(identifier))
        let duplicateResponse = await second.execute()
        if case .some = duplicateResponse {
            Issue.record("A duplicate operation unexpectedly produced an action")
        }

        let response = try #require(await first.execute())
        _ = reducer.reduce(into: &state, action: response)

        #expect(await useCase.enableCount() == 1)
        #expect(!state.isOperating(identifier))
    }

    @Test
    func `load services with partial status failure`() async throws {
        let first = try makeService(identifier: "first")
        let second = try makeService(identifier: "second")
        let useCase = TestServiceManagementUseCase(
            services: [first, second],
            failingStatuses: [second.identifier],
        )
        let reducer = makeReducer(useCase: useCase)
        var state = ServicesState()

        let effect = reducer.reduce(into: &state, action: .refreshServices)
        let response = try #require(await effect.execute())
        _ = reducer.reduce(into: &state, action: response)

        #expect(state.services.map(\.identifier) == [first.identifier, second.identifier])
        #expect(state.statuses[first.identifier]?.registration == .disabled)
        #expect(state.statusFailures == [second.identifier])
    }

    private func makeReducer(useCase: TestServiceManagementUseCase) -> ServicesReducer {
        ServicesReducer(dependencies: ServicesDependencies(
            serviceManagementUseCase: useCase,
            filePanelClient: FilePanelClient(choosePath: { _ in nil }),
            workspaceClient: WorkspaceClient(open: { _ in }, reveal: { _ in }),
        ))
    }

    private func makeService(identifier: String) throws -> ServiceDefinition {
        try ServiceDefinition(
            identifier: ServiceIdentifier(identifier),
            programArguments: ["/usr/bin/true"],
            standardOutPath: "/tmp/\(identifier).out.log",
            standardErrorPath: "/tmp/\(identifier).err.log",
        )
    }
}

private actor TestServiceManagementUseCase: ServiceManagementUseCase {
    struct CreateRequest: Sendable {
        let draft: ServiceDraft
        let enable: Bool
    }

    private var services: [ServiceDefinition]
    private let failingStatuses: Set<ServiceIdentifier>
    private var createRequest: CreateRequest?
    private var enableCallCount = 0

    init(
        services: [ServiceDefinition] = [],
        failingStatuses: Set<ServiceIdentifier> = [],
    ) {
        self.services = services
        self.failingStatuses = failingStatuses
    }

    func list() async throws -> [ServiceDefinition] {
        services
    }

    func find(identifier: ServiceIdentifier) async throws -> ServiceDefinition {
        guard let service = services.first(where: { $0.identifier == identifier }) else {
            throw MoyError.serviceNotFound(identifier.rawValue)
        }
        return service
    }

    func create(_ service: ServiceDraft, enable: Bool) async throws -> ServiceDefinition {
        createRequest = .init(draft: service, enable: enable)
        let definition = ServiceDefinition(
            identifier: service.identifier,
            displayName: service.displayName,
            description: service.description,
            programArguments: service.programArguments,
            workingDirectory: service.workingDirectory,
            environmentVariables: service.environmentVariables,
            runAtLoad: service.runAtLoad,
            keepAlive: service.keepAlive,
            throttleInterval: service.throttleInterval,
            standardOutPath: service.standardOutPath ?? "/tmp/stdout.log",
            standardErrorPath: service.standardErrorPath ?? "/tmp/stderr.log",
        )
        services.append(definition)
        return definition
    }

    func update(_ service: ServiceDefinition) async throws {
        guard let index = services.firstIndex(where: { $0.identifier == service.identifier }) else {
            throw MoyError.serviceNotFound(service.identifier.rawValue)
        }
        services[index] = service
    }

    func remove(identifier: ServiceIdentifier) async throws {
        services.removeAll { $0.identifier == identifier }
    }

    func enable(identifier _: ServiceIdentifier) async throws {
        enableCallCount += 1
    }

    func disable(identifier _: ServiceIdentifier) async throws {}
    func restart(identifier _: ServiceIdentifier) async throws {}

    func status(identifier: ServiceIdentifier) async throws -> ServiceStatus {
        if failingStatuses.contains(identifier) {
            throw MoyError.launchctlFailed(arguments: [], status: 1, message: "test")
        }
        return ServiceStatus(
            identifier: identifier,
            registration: .disabled,
            runtime: .notLoaded,
        )
    }

    func statuses() async throws -> [ServiceStatus] {
        var values: [ServiceStatus] = []
        for service in services {
            try await values.append(status(identifier: service.identifier))
        }
        return values
    }

    func lastCreateRequest() -> CreateRequest? {
        createRequest
    }

    func enableCount() -> Int {
        enableCallCount
    }
}
