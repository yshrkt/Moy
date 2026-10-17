import Foundation
@testable import MoyApp
import MoyKit
import NanoRedux
import Testing

struct ServiceEditorIdentifierValidationTests {
    @Test
    func `empty identifiers show the required message before input and after debounce`() async throws {
        let reducer = ServiceEditorReducer(dependencies: .init())
        var editor = ServiceEditorState.create()
        editor.executable = "/usr/bin/true"
        #expect(editor.identifierIssue == .invalidFormat(.empty))
        #expect(!editor.canSave)
        try await validate("worker", reducer: reducer, editor: &editor)
        #expect(editor.canSave)

        let effect = reducer.reduce(into: &editor, action: .updateEditor(.identifier("")))
        #expect(editor.identifier.isEmpty)
        #expect(editor.validatingIdentifier != nil)
        #expect(editor.identifierIssue == nil)
        #expect(!editor.canSave)
        _ = try reducer.reduce(into: &editor, action: #require(await effect.executeForTesting()))
        #expect(editor.identifierIssue == .invalidFormat(.empty))
        #expect(!editor.canSave)
    }

    @Test(arguments: ["API", "api server", "-api", "api_", String(repeating: "a", count: 65)])
    func `invalid input is preserved and saving waits for validation`(value: String) async throws {
        let reducer = ServiceEditorReducer(dependencies: .init())
        var editor = ServiceEditorState.create()
        editor.executable = "/usr/bin/true"
        let update = reducer.reduce(into: &editor, action: .updateEditor(.identifier(value)))
        #expect(editor.identifier == value)
        #expect(editor.validatingIdentifier != nil)
        #expect(editor.identifierIssue == .invalidFormat(.empty))
        #expect(!editor.canSave)
        let pendingSave = reducer.reduce(into: &editor, action: .saveService)
        #expect(await pendingSave.executeForTesting() == nil)
        #expect(!editor.isSaving)
        _ = try reducer.reduce(into: &editor, action: #require(await update.executeForTesting()))
        #expect(editor.identifierIssue != nil)
        let invalidSave = reducer.reduce(into: &editor, action: .saveService)
        #expect(await invalidSave.executeForTesting() == nil)
        let previousIssue = try #require(editor.identifierIssue)
        let correction = reducer.reduce(into: &editor, action: .updateEditor(.identifier("worker")))
        #expect(editor.identifierIssue == previousIssue)
        #expect(!editor.canSave)
        _ = try reducer.reduce(into: &editor, action: #require(await correction.executeForTesting()))
        #expect(editor.identifierIssue == nil)
        #expect(editor.canSave)
    }

    @Test
    func `cached list duplicates cannot emit a save request`() async throws {
        let useCase = TestServiceManagementUseCase()
        let reducer = ServicesReducer(dependencies: .init(serviceManagementUseCase: useCase))
        var state = ServicesState()
        state.services = try [service("worker")]
        _ = reducer.reduce(into: &state, action: .presentCreateService)
        _ = reducer.reduce(into: &state, action: .editor(.updateEditor(.executable("/usr/bin/true"))))
        let update = reducer.reduce(into: &state, action: .editor(.updateEditor(.identifier("worker"))))
        _ = try reducer.reduce(into: &state, action: #require(await update.executeForTesting()))
        let editor = try #require(state.editor)
        #expect(editor.identifierIssue == .duplicate)
        #expect(!editor.canSave)
        let save = reducer.reduce(into: &state, action: .editor(.saveService))
        #expect(await save.executeForTesting() == nil)
        #expect(await useCase.lastCreateRequest() == nil)
        #expect(!editor.isSaving)
        #expect(editor.failure == nil)
    }

    @Test
    func `refreshed lists schedule validation and unchanged lists keep the pending input`() async throws {
        let reducer = ServiceEditorReducer(dependencies: .init())
        var editor = ServiceEditorState.create()
        editor.executable = "/usr/bin/true"
        _ = reducer.reduce(into: &editor, action: .updateEditor(.identifier("worker")))
        let refreshed = reducer.reduce(into: &editor, action: .updateExistingIdentifiers(["worker"]))
        let input = editor.validatingIdentifier
        let unchanged = reducer.reduce(into: &editor, action: .updateExistingIdentifiers(["worker"]))
        #expect(await unchanged.executeForTesting() == nil)
        #expect(editor.validatingIdentifier == input)
        #expect(!editor.canSave)
        _ = try reducer.reduce(into: &editor, action: #require(await refreshed.executeForTesting()))
        #expect(editor.identifierIssue == .duplicate)
        let removed = reducer.reduce(into: &editor, action: .updateExistingIdentifiers([]))
        _ = try reducer.reduce(into: &editor, action: #require(await removed.executeForTesting()))
        #expect(editor.canSave)
    }

    @Test
    func `parent list refresh schedules validation in the existing editor`() async throws {
        let reducer = ServicesReducer(dependencies: .init(serviceManagementUseCase: TestServiceManagementUseCase()))
        var state = ServicesState()
        _ = reducer.reduce(into: &state, action: .presentCreateService)
        let input = reducer.reduce(into: &state, action: .editor(.updateEditor(.identifier("worker"))))
        _ = try reducer.reduce(into: &state, action: #require(await input.executeForTesting()))
        _ = reducer.reduce(into: &state, action: .editor(.updateEditor(.executable("/usr/bin/true"))))
        let editor = try #require(state.editor)
        let refreshed = try reducer.reduce(into: &state, action: .receiveServices(.success(.init(
            services: [service("worker")], statuses: [:], statusFailures: [],
        ))))
        #expect(state.editor === editor)
        #expect(!editor.canSave)
        _ = try reducer.reduce(into: &state, action: #require(await refreshed.executeForTesting()))
        #expect(editor.identifierIssue == .duplicate)
    }

    @Test
    func `results for other input or another session are ignored and matching input is accepted`() async throws {
        let reducer = ServiceEditorReducer(dependencies: .init())
        var editor = ServiceEditorState.create()
        editor.executable = "/usr/bin/true"
        let old = reducer.reduce(into: &editor, action: .updateEditor(.identifier("worker")))
        let oldResult = try #require(await old.executeForTesting())
        _ = reducer.reduce(into: &editor, action: .updateEditor(.identifier("other")))
        _ = reducer.reduce(into: &editor, action: oldResult)
        #expect(editor.validatingIdentifier == "other")
        #expect(!editor.canSave)
        let latest = reducer.reduce(into: &editor, action: .updateEditor(.identifier("worker")))
        _ = reducer.reduce(into: &editor, action: oldResult)
        #expect(editor.validatingIdentifier == nil)
        #expect(editor.canSave)
        let latestResult = try #require(await latest.executeForTesting())
        _ = reducer.reduce(into: &editor, action: latestResult)
        #expect(editor.canSave)
        editor = .create()
        _ = reducer.reduce(into: &editor, action: latestResult)
        #expect(editor.identifierIssue == .invalidFormat(.empty))
        #expect(editor.identifier.isEmpty)
    }

    @MainActor
    @Test
    func `runtime waits for settled input before accepting the latest validation`() async throws {
        let editor = ServiceEditorState.create()
        editor.executable = "/usr/bin/true"
        let store = Store.reducer(initialState: editor, reducer: ServiceEditorReducer(dependencies: .init()))
        store.send(.updateEditor(.identifier("API")))
        try await Task.sleep(for: .milliseconds(100))
        #expect(editor.identifier == "API")
        #expect(editor.validatingIdentifier != nil)
        #expect(editor.identifierIssue == .invalidFormat(.empty))
        store.send(.updateEditor(.identifier("worker")))
        try await Task.sleep(for: .milliseconds(100))
        #expect(!editor.canSave)
        #expect(editor.validatingIdentifier != nil)
        try await Task.sleep(for: .milliseconds(500))
        #expect(editor.identifier == "worker")
        #expect(editor.validatingIdentifier == nil)
        #expect(editor.identifierIssue == nil)
        #expect(editor.canSave)
    }

    @Test
    func `editing an existing service does not validate its immutable identifier`() throws {
        let reducer = ServiceEditorReducer(dependencies: .init())
        var editor = try ServiceEditorState(service: service("worker"))
        _ = reducer.reduce(into: &editor, action: .updateExistingIdentifiers(["worker"]))
        _ = reducer.reduce(into: &editor, action: .updateEditor(.identifier("other")))
        #expect(editor.identifier == "worker")
        #expect(editor.validatingIdentifier == nil)
        #expect(editor.identifierIssue == nil)
        #expect(editor.canSave)
    }

    private func validate(
        _ value: String,
        reducer: ServiceEditorReducer,
        editor: inout ServiceEditorState,
    ) async throws {
        let effect = reducer.reduce(into: &editor, action: .updateEditor(.identifier(value)))
        _ = try reducer.reduce(into: &editor, action: #require(await effect.executeForTesting()))
    }

    private func service(_ identifier: String) throws -> ServiceDefinition {
        try ServiceDefinition(
            identifier: ServiceIdentifier(identifier),
            programArguments: ["/usr/bin/true"],
            standardOutPath: "/tmp/\(identifier).out",
            standardErrorPath: "/tmp/\(identifier).err",
        )
    }
}
