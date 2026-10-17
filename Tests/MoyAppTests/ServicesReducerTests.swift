@testable import MoyApp
import MoyKit
import NanoRedux
import Testing

@Suite("Services reducer")
struct ServicesReducerTests {
    @Test
    func `create service without enabling`() async throws {
        let useCase = TestServiceManagementUseCase()
        let reducer = makeReducer(useCase: useCase)
        var state = ServicesState()

        _ = reducer.reduce(into: &state, action: .presentCreateService)
        let validation = reducer.reduce(into: &state, action: .editor(.updateField(.identifier("api-server"))))
        let validated = try #require(await validation.executeForTesting())
        _ = reducer.reduce(into: &state, action: validated)
        _ = reducer.reduce(into: &state, action: .editor(.updateField(.displayName("API Server"))))
        _ = reducer.reduce(into: &state, action: .editor(.updateField(.executable("/usr/bin/python3"))))
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.add)))
        let argumentID = try #require(state.editor?.arguments.first?.id)
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.update(argumentID, ""))))
        _ = reducer.reduce(into: &state, action: .editor(.environment(.add)))
        let variableID = try #require(state.editor?.environmentVariables.first?.id)
        _ = reducer.reduce(into: &state, action: .editor(.environment(.updateKey(variableID, "MODE"))))
        _ = reducer.reduce(
            into: &state,
            action: .editor(.environment(.updateValue(variableID, "development"))),
        )

        let effect = reducer.reduce(into: &state, action: .editor(.save))
        #expect(state.editor?.isSaving == true)
        let response = try #require(await effect.executeForTesting())
        let saveEffect = reducer.reduce(into: &state, action: response)
        let saveResult = try #require(await saveEffect.executeForTesting())
        _ = reducer.reduce(into: &state, action: saveResult)

        let request = try #require(await useCase.lastCreateRequest())
        #expect(!request.enable)
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

        let first = reducer.reduce(into: &state, action: .operation(.enable(identifier)))
        let second = reducer.reduce(into: &state, action: .operation(.enable(identifier)))
        #expect(state.isOperating(identifier))
        let duplicateResponse = await second.executeForTesting()
        if case .some = duplicateResponse {
            Issue.record("A duplicate operation unexpectedly produced an action")
        }

        let response = try #require(await first.executeForTesting())
        let refresh = reducer.reduce(into: &state, action: response)

        #expect(await useCase.enableCount() == 1)
        #expect(!state.isOperating(identifier))
        guard case .refreshServices = await refresh.executeForTesting() else {
            Issue.record("Completing an operation must refresh the service list")
            return
        }
    }

    @Test
    func `deletion confirms once and refreshes services after clearing selection`() async throws {
        let service = try makeService(identifier: "worker")
        let useCase = TestServiceManagementUseCase(services: [service])
        let reducer = makeReducer(useCase: useCase)
        var state = ServicesState()
        state.services = [service]
        state.selectedIdentifier = service.identifier

        let unconfirmed = reducer.reduce(into: &state, action: .deletion(.confirm))
        #expect(await unconfirmed.executeForTesting() == nil)
        _ = reducer.reduce(into: &state, action: .deletion(.request(service.identifier)))
        #expect(state.pendingDeletion == service.identifier)
        _ = reducer.reduce(into: &state, action: .deletion(.cancel))
        #expect(state.pendingDeletion == nil)
        _ = reducer.reduce(into: &state, action: .deletion(.request(service.identifier)))
        let deletion = reducer.reduce(into: &state, action: .deletion(.confirm))
        #expect(state.pendingDeletion == nil)
        #expect(state.isOperating(service.identifier))
        let duplicate = reducer.reduce(into: &state, action: .deletion(.confirm))
        let overlap = reducer.reduce(into: &state, action: .operation(.enable(service.identifier)))
        #expect(await duplicate.executeForTesting() == nil)
        #expect(await overlap.executeForTesting() == nil)

        let response = try #require(await deletion.executeForTesting())
        let refresh = reducer.reduce(into: &state, action: response)
        #expect(!state.isOperating(service.identifier))
        #expect(state.selectedIdentifier == nil)
        let refreshAction = try #require(await refresh.executeForTesting())
        guard case .refreshServices = refreshAction else {
            Issue.record("Completing deletion must refresh the service list")
            return
        }
        let load = reducer.reduce(into: &state, action: refreshAction)
        _ = try reducer.reduce(into: &state, action: #require(await load.executeForTesting()))
        #expect(state.services.isEmpty)
    }

    @Test(arguments: [ServicesFailure.cancelled, .unexpected("test failure")])
    func `failed operations preserve selection and refresh the service list`(failure: ServicesFailure) async throws {
        let identifier = try ServiceIdentifier("worker")
        let reducer = makeReducer(useCase: TestServiceManagementUseCase())
        for action in [
            ServicesAction.operation(.receive(identifier, .failure(failure))),
            .deletion(.receive(identifier, .failure(failure))),
        ] {
            var state = ServicesState()
            state.selectedIdentifier = identifier
            state.operatingIdentifiers.insert(identifier)
            let refresh = reducer.reduce(into: &state, action: action)
            #expect(!state.isOperating(identifier))
            #expect(state.selectedIdentifier == identifier)
            #expect(state.failure == (failure == .cancelled ? nil : failure))
            guard case .refreshServices = await refresh.executeForTesting() else {
                Issue.record("Failure or cancellation must refresh the service list")
                return
            }
        }
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
        let response = try #require(await effect.executeForTesting())
        _ = reducer.reduce(into: &state, action: response)

        #expect(state.services.map(\.identifier) == [first.identifier, second.identifier])
        #expect(state.statuses[first.identifier]?.registration == .disabled)
        #expect(state.statusFailures == [second.identifier])
    }

    private func makeReducer(useCase: TestServiceManagementUseCase) -> ServicesReducer {
        ServicesReducer(dependencies: ServicesDependencies(
            serviceManagementUseCase: useCase,
            editor: ServiceEditorDependencies(filePanelClient: FilePanelClient(choosePath: { _ in nil })),
            workspaceClient: WorkspaceClient(open: { _ in }, reveal: { _ in }),
        ))
    }

    @Test
    func `log operations forward the original paths`() async throws {
        let requests = LogOperationRequests()
        let reducer = ServicesReducer(dependencies: ServicesDependencies(
            serviceManagementUseCase: TestServiceManagementUseCase(),
            workspaceClient: WorkspaceClient(
                open: { await requests.recordOpen($0) },
                reveal: { await requests.recordReveal($0) },
            ),
        ))
        var state = ServicesState()
        let paths = ["/tmp/standard out.log", "/tmp/standard 'error'.log"]
        for path in paths {
            let open = reducer.reduce(into: &state, action: .openLog(path))
            let openResponse = try #require(await open.executeForTesting())
            _ = reducer.reduce(into: &state, action: openResponse)
            let reveal = reducer.reduce(into: &state, action: .revealLog(path))
            let revealResponse = try #require(await reveal.executeForTesting())
            _ = reducer.reduce(into: &state, action: revealResponse)
        }
        #expect(await requests.opened == paths)
        #expect(await requests.revealed == paths)
        #expect(state.failure == nil)
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

private actor LogOperationRequests {
    var opened: [String] = []
    var revealed: [String] = []

    func recordOpen(_ path: String) {
        opened.append(path)
    }

    func recordReveal(_ path: String) {
        revealed.append(path)
    }
}

actor TestServiceManagementUseCase: ServiceManagementUseCase {
    struct CreateRequest: Sendable {
        let draft: ServiceDraft
        let enable: Bool
    }

    private var services: [ServiceDefinition]
    private let registration: ServiceStatus.Registration
    private let failingStatuses: Set<ServiceIdentifier>
    private var createRequest: CreateRequest?
    private var enableCallCount = 0

    init(
        services: [ServiceDefinition] = [],
        failingStatuses: Set<ServiceIdentifier> = [],
        registration: ServiceStatus.Registration = .disabled,
    ) {
        self.registration = registration
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
            kind: service.kind,
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
            registration: registration,
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
