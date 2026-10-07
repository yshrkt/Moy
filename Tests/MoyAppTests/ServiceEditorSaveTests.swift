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
    @Test(arguments: [false, true], [false, true])
    func `missing executables fail without saving and can be corrected`(enable: Bool, commandOnly: Bool) async throws {
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
                launchAgentRepository: LaunchctlAgentRepository(paths: paths),
            ),
        ))
        var state = ServicesState()
        _ = reducer.reduce(into: &state, action: .presentCreateService)
        _ = reducer.reduce(into: &state, action: .updateEditor(.identifier("invalid-command")))
        let invalidPath = commandOnly ? "unknown-command" : root.appending(path: "missing-tool").path
        _ = reducer.reduce(into: &state, action: .updateEditor(.executable(invalidPath)))

        let effect = reducer.reduce(into: &state, action: .saveService(enable: enable))
        #expect(state.isSaving)
        let response = try #require(await effect.execute())
        _ = reducer.reduce(into: &state, action: response)
        let failure = try #require(state.failure)
        #expect(failure == .moy(.executableNotFound(invalidPath)))
        #expect(failure.localizedMessage.contains(L10n.Error.executableNotFound))
        #expect(!state.isSaving)
        #expect(state.editor?.executable == invalidPath)
        #expect(try await repository.list().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: paths.servicesFile.path))

        _ = reducer.reduce(into: &state, action: .updateEditor(.executable("/usr/bin/true")))
        let retry = reducer.reduce(into: &state, action: .saveService(enable: false))
        #expect(state.failure == nil)
        let saved = try #require(await retry.execute())
        _ = reducer.reduce(into: &state, action: saved)
        #expect(state.editor == nil)
        #expect(!state.isSaving)
        #expect(try await repository.list().first?.programArguments == ["/usr/bin/true"])
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
        let host = NSHostingView(rootView: ServiceEditorView(store: store))
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
        state.failure = .moy(.executableNotFound("unknown-command"))
        try await Task.sleep(for: .milliseconds(300))

        #expect(window.attachedSheet != nil)
        #expect(state.editor != nil)
        state.failure = nil
        try await Task.sleep(for: .milliseconds(300))
        #expect(window.attachedSheet == nil)
    }

    @Test
    func `payload validation failures retain input and clear when dismissed`() {
        let reducer = ServicesReducer(dependencies: ServicesDependencies(
            serviceManagementUseCase: TestServiceManagementUseCase(),
        ))
        var state = ServicesState()
        _ = reducer.reduce(into: &state, action: .presentCreateService)
        _ = reducer.reduce(into: &state, action: .updateEditor(.identifier("worker")))
        _ = reducer.reduce(into: &state, action: .updateEditor(.executable("/usr/bin/true")))
        _ = reducer.reduce(into: &state, action: .updateEditor(.throttleInterval("abc")))
        _ = reducer.reduce(into: &state, action: .saveService(enable: false))
        #expect(state.failure == .invalidThrottleInterval)
        #expect(state.editor?.throttleInterval == "abc")
        #expect(!state.isSaving)

        _ = reducer.reduce(into: &state, action: .dismissEditor)
        #expect(state.failure == nil)
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
