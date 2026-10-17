import Foundation
@testable import MoyApp
import MoyKit
import NanoRedux
import Testing

@Suite("Service editor reducer")
struct ServiceEditorReducerTests {
    @Test
    func `saving freezes input and emits a validated snapshot once`() async throws {
        let reducer = ServiceEditorReducer(dependencies: .init())
        var state = ServiceEditorState.create()
        state.identifier = "worker"
        state.executable = "/usr/bin/true"
        let effect = reducer.reduce(into: &state, action: .saveService)
        #expect(state.isSaving)
        _ = reducer.reduce(into: &state, action: .updateEditor(.displayName("changed")))
        _ = reducer.reduce(into: &state, action: .arguments(.addArgument))
        #expect(state.displayName.isEmpty)
        #expect(state.arguments.isEmpty)
        let duplicate = reducer.reduce(into: &state, action: .saveService)
        #expect(await duplicate.executeForTesting() == nil)
        let action = try #require(await effect.executeForTesting())
        guard case let .delegate(.save(id, .create(identifier, draft))) = action else {
            Issue.record("Expected a create payload delegate")
            return
        }
        #expect(id == state.id)
        #expect(identifier.rawValue == "worker")
        #expect(draft.programArguments == ["/usr/bin/true"])
    }

    @Test
    func `path selection from an old session does not modify the next editor`() async throws {
        let reducer = ServiceEditorReducer(dependencies: .init(
            filePanelClient: FilePanelClient(choosePath: { _ in "/usr/bin/true" }),
        ))
        var state = ServiceEditorState.create()
        let effect = reducer.reduce(into: &state, action: .chooseEditorPath(.executable))
        state = .create()
        let action = try #require(await effect.executeForTesting())
        let ignored = reducer.reduce(into: &state, action: action)
        #expect(await ignored.executeForTesting() == nil)
        #expect(state.executable.isEmpty)
        let current = reducer.reduce(into: &state, action: .chooseEditorPath(.executable))
        let selected = try #require(await current.executeForTesting())
        _ = reducer.reduce(into: &state, action: selected)
        #expect(state.executable == "/usr/bin/true")
    }

    @Test
    func `editing preserves the identifier`() throws {
        let service = try ServiceDefinition(
            identifier: ServiceIdentifier("worker"),
            programArguments: ["/usr/bin/true"],
            standardOutPath: "/tmp/out.log",
            standardErrorPath: "/tmp/err.log",
        )
        var state = ServiceEditorState(service: service)
        let reducer = ServiceEditorReducer(dependencies: .init())
        _ = reducer.reduce(into: &state, action: .updateEditor(.identifier("other")))
        #expect(state.identifier == "worker")
    }

    @Test
    func `save failure stays in the child and stale results leave the next session intact`() async throws {
        let reducer = ServicesReducer(dependencies: .init(
            serviceManagementUseCase: TestServiceManagementUseCase(),
        ))
        var state = ServicesState()
        _ = reducer.reduce(into: &state, action: .presentCreateService)
        let editor = try #require(state.editor)
        editor.identifier = "worker"
        editor.executable = "/usr/bin/true"
        editor.isSaving = true
        let parentFailure = ServicesFailure.unexpected("list failure")
        state.failure = parentFailure
        _ = try reducer.reduce(into: &state, action: .receiveSave(
            editor.id, ServiceIdentifier("worker"), .failure(.invalidThrottleInterval),
        ))
        #expect(editor.failure == .invalidThrottleInterval)
        #expect(!editor.isSaving)
        #expect(state.failure == parentFailure)
        let cancel = reducer.reduce(into: &state, action: .editor(.cancel))
        let dismissal = try #require(await cancel.executeForTesting())
        _ = reducer.reduce(into: &state, action: dismissal)
        #expect(state.editor == nil)
        _ = reducer.reduce(into: &state, action: .presentCreateService)
        let next = try #require(state.editor)
        _ = try reducer.reduce(into: &state, action: .receiveSave(
            editor.id, ServiceIdentifier("worker"), .success(()),
        ))
        #expect(state.editor === next)
        #expect(next.failure == nil)
        #expect(state.selectedIdentifier == nil)
    }
}
