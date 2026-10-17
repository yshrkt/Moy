import Foundation
@testable import MoyApp
import MoyKit
import Testing

@MainActor
struct DaemonAuthorizationTests {
    @Test
    func `kind is selectable only for ordinary creation`() throws {
        let reducer = ServiceEditorReducer(dependencies: .init())
        var editor = ServiceEditorState.create()
        _ = reducer.reduce(into: &editor, action: .updateField(.kind(.launchDaemon)))
        #expect(editor.kind == .launchDaemon)
        let draft = try ServiceDraft(
            identifier: ServiceIdentifier("import-daemon"), kind: .launchDaemon, programArguments: ["/usr/bin/true"],
        )
        editor = .create(draft: draft, existingIdentifiers: [])
        _ = reducer.reduce(into: &editor, action: .updateField(.kind(.launchAgent)))
        #expect(editor.kind == .launchDaemon)
        if case let .create(_, saved) = try ServiceEditorPayload(editor: editor) {
            #expect(saved.kind == .launchDaemon)
        } else {
            Issue.record("Expected a create payload")
        }
        editor = try .init(service: daemon())
        _ = reducer.reduce(into: &editor, action: .updateField(.kind(.launchAgent)))
        #expect(editor.kind == .launchDaemon)
        if case let .update(saved) = try ServiceEditorPayload(editor: editor) {
            #expect(saved.kind == .launchDaemon)
        } else {
            Issue.record("Expected an update payload")
        }
    }

    @Test
    func `cancelling authorization leaves definitions and editor input unchanged`() async throws {
        let original = try daemon()
        let base = TestServiceManagementUseCase(services: [original], registration: .enabled)
        let services = AuthorizedServiceManagementUseCase(
            base: base, authorization: .init(execute: { _ in throw CancellationError() }),
            executable: URL(filePath: "/usr/bin/true"),
        )
        var changed = original
        changed.runAtLoad = true
        await #expect(throws: CancellationError.self) { try await services.update(changed) }
        #expect(try await base.find(identifier: original.identifier) == original)
        let reducer = ServicesReducer(dependencies: .init(serviceManagementUseCase: services))
        var state = ServicesState()
        state.editor = .init(service: changed)
        let editor = try #require(state.editor)
        editor.isSaving = true
        _ = reducer.reduce(into: &state, action: .receiveSave(editor.id, original.identifier, .failure(.cancelled)))
        #expect(state.editor === editor)
        #expect(editor.runAtLoad)
        #expect(!editor.isSaving)
        #expect(editor.failure == nil)
        #expect(state.failure == nil)
    }

    @Test
    func `metadata edits do not request administrator authorization`() async throws {
        let original = try daemon()
        let base = TestServiceManagementUseCase(services: [original], registration: .enabled)
        let services = AuthorizedServiceManagementUseCase(
            base: base, authorization: .init(execute: { _ in
                Issue.record("Unexpected administrator authentication")
                throw CancellationError()
            }),
        )
        var changed = original
        changed.displayName = "New name"
        try await services.update(changed)
        #expect(try await base.find(identifier: original.identifier) == changed)
    }

    @Test
    func `authorized response preserves typed application failures`() async throws {
        let original = try daemon()
        let base = TestServiceManagementUseCase(services: [original], registration: .enabled)
        let error = MoyError.serviceUpdateNotApplied(identifier: original.identifier.rawValue, reason: "Test failure")
        let data = try JSONEncoder().encode(DaemonOperationResult(error: error))
        let response = try #require(String(data: data, encoding: .utf8))
        let services = AuthorizedServiceManagementUseCase(
            base: base, authorization: .init(execute: { _ in response }), executable: URL(filePath: "/usr/bin/true"),
        )
        var changed = original
        changed.runAtLoad = true
        await #expect(throws: error) { try await services.update(changed) }
    }

    @Test
    func `shared AppleScript maps cancellation without administrator prompt`() async throws {
        await #expect(throws: CancellationError.self) {
            try await AppleScriptClient.live.execute(
                "on cancelRequest()\nerror number -128\nend cancelRequest", "cancelRequest", [],
            )
        }
    }

    private func daemon() throws -> ServiceDefinition {
        try ServiceDefinition(
            identifier: ServiceIdentifier("gui-daemon"), kind: .launchDaemon, programArguments: ["/usr/bin/true"],
            standardOutPath: "/tmp/gui-daemon.out", standardErrorPath: "/tmp/gui-daemon.err",
        )
    }
}
