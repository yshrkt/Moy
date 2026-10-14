import AppKit
import Foundation
@testable import MoyApp
import MoyKit
import NanoRedux
import SwiftUI
import Testing

@MainActor
@Suite("Service editor save failures", .serialized)
struct ServiceEditorSaveTests {
    @Test(arguments: [false, true])
    func `missing executables fail without saving and can be corrected`(commandOnly: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MoyEditorSave-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = MoyPaths(
            dataDirectory: root.appending(path: "data"),
            launchAgentsDirectory: root.appending(path: "agents"),
            logDirectory: root.appending(path: "logs"),
        )
        let repository = JSONServiceRepository(paths: paths, labelChecker: UnloadedLabelChecker())
        let reducer = ServicesReducer(dependencies: ServicesDependencies(
            serviceManagementUseCase: DefaultServiceManagementUseCase(
                serviceRepository: repository,
                launchAgentRepository: LaunchctlServiceRepository(paths: paths),
            ),
        ))
        var state = ServicesState()
        _ = reducer.reduce(into: &state, action: .presentCreateService)
        let validation = reducer.reduce(into: &state, action: .editor(.updateEditor(.identifier("invalid-command"))))
        let validated = try #require(await validation.execute())
        _ = reducer.reduce(into: &state, action: validated)
        let invalidPath = commandOnly ? "unknown-command" : root.appending(path: "missing-tool").path
        _ = reducer.reduce(into: &state, action: .editor(.updateEditor(.executable(invalidPath))))

        let effect = reducer.reduce(into: &state, action: .editor(.saveService))
        #expect(state.editor?.isSaving == true)
        let response = try #require(await effect.execute())
        let saveEffect = reducer.reduce(into: &state, action: response)
        let saveResult = try #require(await saveEffect.execute())
        _ = reducer.reduce(into: &state, action: saveResult)
        let failure = try #require(state.editor?.failure)
        #expect(failure == .moy(.executableNotFound(invalidPath)))
        #expect(failure.localizedMessage.contains(L10n.Error.executableNotFound))
        #expect(state.editor?.isSaving != true)
        #expect(state.editor?.executable == invalidPath)
        #expect(try await repository.list().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: paths.servicesFile.path))

        _ = reducer.reduce(into: &state, action: .editor(.updateEditor(.executable("/usr/bin/true"))))
        let retry = reducer.reduce(into: &state, action: .editor(.saveService))
        #expect(state.editor?.failure == nil)
        let saved = try #require(await retry.execute())
        let retryEffect = reducer.reduce(into: &state, action: saved)
        let retryResult = try #require(await retryEffect.execute())
        _ = reducer.reduce(into: &state, action: retryResult)
        #expect(state.editor == nil)
        #expect(state.editor?.isSaving != true)
        #expect(try await repository.list().first?.programArguments == ["/usr/bin/true"])
        let plistPath = try paths.plistFile(identifier: ServiceIdentifier("invalid-command")).path
        #expect(!FileManager.default.fileExists(atPath: plistPath))
    }

    @Test
    func `saved but unapplied update closes editor and refreshes with recovery notice`() async throws {
        let service = try ServiceDefinition(
            identifier: ServiceIdentifier("update-notice"),
            programArguments: ["/usr/bin/true"],
            standardOutPath: "/tmp/update-notice.out",
            standardErrorPath: "/tmp/update-notice.err",
        )
        var updated = service
        updated.programArguments = ["/usr/bin/true", "argument"]
        let reducer = ServicesReducer(dependencies: ServicesDependencies(
            serviceManagementUseCase: TestServiceManagementUseCase(services: [updated]),
        ))
        var state = ServicesState()
        state.services = [service]
        _ = reducer.reduce(into: &state, action: .presentEditService(service.identifier))
        let editor = try #require(state.editor)
        editor.isSaving = true
        let error = MoyError.serviceUpdateNotApplied(identifier: service.identifier.rawValue, reason: "forced failure")
        let effect = reducer.reduce(into: &state, action: .receiveSave(
            editor.id, service.identifier, .failure(.moy(error)),
        ))
        #expect(state.editor == nil)
        #expect(state.failure == .moy(error))
        #expect(state.selectedIdentifier == service.identifier)
        let expectedMessage = "\(L10n.Error.serviceUpdateNotApplied)\nupdate-notice\nforced failure"
        #expect(state.failure?.localizedMessage == expectedMessage)
        let refresh = try #require(await effect.execute())
        let snapshotEffect = reducer.reduce(into: &state, action: refresh)
        let snapshot = try #require(await snapshotEffect.execute())
        _ = reducer.reduce(into: &state, action: snapshot)
        #expect(state.selectedService == updated)
        #expect(state.statuses[service.identifier]?.registration == .disabled)
        #expect(state.failure == .moy(error))
    }

    @Test
    func `editor presents its own error alert`() async throws {
        let state = ServicesState()
        state.editor = .create()
        let store = Store.reducer(
            initialState: state,
            reducer: ServicesReducer(dependencies: ServicesDependencies(
                serviceManagementUseCase: TestServiceManagementUseCase(),
            )),
        )
        let editor = try #require(state.editor)
        let editorStore = store.scope(state: { _ in editor }, action: ServicesAction.editor)
        let host = NSHostingView(rootView: ServiceEditorView(store: editorStore))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 680),
            styleMask: [.titled], backing: .buffered, defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            for sheet in window.sheets {
                window.endSheet(sheet)
                sheet.orderOut(nil)
            }
            window.close()
        }
        window.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        state.editor?.failure = .moy(.executableNotFound("unknown-command"))
        try await Task.sleep(for: .milliseconds(300))

        #expect(window.attachedSheet != nil)
        #expect(state.editor != nil)
        state.editor?.failure = nil
        try await Task.sleep(for: .milliseconds(300))
        #expect(window.attachedSheet == nil)
    }

    @Test
    func `payload validation failures retain input and clear when dismissed`() async throws {
        let reducer = ServicesReducer(dependencies: ServicesDependencies(
            serviceManagementUseCase: TestServiceManagementUseCase(),
        ))
        var state = ServicesState()
        _ = reducer.reduce(into: &state, action: .presentCreateService)
        let validation = reducer.reduce(into: &state, action: .editor(.updateEditor(.identifier("worker"))))
        let validated = try #require(await validation.execute())
        _ = reducer.reduce(into: &state, action: validated)
        _ = reducer.reduce(into: &state, action: .editor(.updateEditor(.executable("/usr/bin/true"))))
        _ = reducer.reduce(into: &state, action: .editor(.updateEditor(.throttleInterval("abc"))))
        _ = reducer.reduce(into: &state, action: .editor(.saveService))
        #expect(state.editor?.failure == .invalidThrottleInterval)
        #expect(state.editor?.throttleInterval == "abc")
        #expect(state.editor?.isSaving != true)

        let cancel = reducer.reduce(into: &state, action: .editor(.cancel))
        let dismissal = try #require(await cancel.execute())
        _ = reducer.reduce(into: &state, action: dismissal)
        #expect(state.editor?.failure == nil)
        #expect(state.editor == nil)
        state.failure = .invalidThrottleInterval
        _ = reducer.reduce(into: &state, action: .presentCreateService)
        #expect(state.failure == nil)
    }
}

private struct UnloadedLabelChecker: ServiceLabelChecking {
    func isLoaded(label _: String) async throws -> Bool {
        false
    }
}
