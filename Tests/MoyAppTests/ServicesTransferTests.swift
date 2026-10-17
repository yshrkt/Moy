import Foundation
@testable import MoyApp
import MoyKit
import NanoRedux
import Testing

struct ServicesTransferTests {
    @Test
    func `import fills a new editable service without registering or enabling`() async throws {
        let draft = try makeDraft()
        let transfer = TransferUseCaseStub(draft: draft)
        let management = TestServiceManagementUseCase()
        let reducer = makeReducer(transfer: transfer, management: management)
        var state = ServicesState()
        let effect = reducer.reduce(into: &state, action: .transfer(.importService))
        #expect(state.transferOperation == .importService)
        #expect(!state.canOpenEditor)
        let duplicate = reducer.reduce(into: &state, action: .transfer(.importService))
        #expect(await duplicate.executeForTesting() == nil)
        _ = reducer.reduce(into: &state, action: .presentCreateService)
        #expect(state.editor == nil)
        _ = try reducer.reduce(into: &state, action: #require(await effect.executeForTesting()))
        let editor = try #require(state.editor)
        #expect(editor.mode == .create)
        #expect(editor.identifier == draft.identifier.rawValue)
        #expect(editor.displayName == draft.displayName)
        #expect(editor.serviceDescription == draft.description)
        #expect(editor.executable == "/missing/tool")
        #expect(editor.arguments.map(\.value) == ["", "hello world", "$PORT"])
        #expect(editor.environmentVariables.map(\.key) == ["A", "Z"])
        #expect(editor.workingDirectory == "/tmp")
        #expect(editor.runAtLoad && editor.keepAlive)
        #expect(editor.throttleInterval == "12")
        #expect(editor.standardOutPath.isEmpty)
        #expect(editor.standardErrorPath == "/tmp/custom.stderr.log")
        #expect(editor.identifierIssue == nil)
        #expect(state.transferOperation == nil)
        #expect(await transfer.importCalls == 0)
        #expect(await management.lastCreateRequest() == nil)
        let payload = try ServiceEditorPayload(editor: editor)
        guard case let .create(_, copied) = payload else {
            Issue.record("Expected new-service payload")
            return
        }
        #expect(copied == draft)
    }

    @Test
    func `duplicate imports show inline errors and become saveable after identifier correction`() async throws {
        let draft = try makeDraft()
        let management = TestServiceManagementUseCase()
        let reducer = makeReducer(transfer: TransferUseCaseStub(draft: draft), management: management)
        var state = ServicesState()
        state.services = [definition(draft)]
        let effect = reducer.reduce(into: &state, action: .transfer(.importService))
        _ = try reducer.reduce(into: &state, action: #require(await effect.executeForTesting()))
        let editor = try #require(state.editor)
        #expect(editor.identifierIssue == .duplicate)
        #expect(!editor.canSave)
        #expect(state.failure == nil)
        let correction = reducer.reduce(into: &state, action: .editor(.updateField(.identifier("new-service"))))
        _ = try reducer.reduce(into: &state, action: #require(await correction.executeForTesting()))
        #expect(editor.canSave)
        let save = reducer.reduce(into: &state, action: .editor(.save))
        let delegate = try #require(await save.executeForTesting())
        let create = reducer.reduce(into: &state, action: delegate)
        _ = try reducer.reduce(into: &state, action: #require(await create.executeForTesting()))
        let request = try #require(await management.lastCreateRequest())
        #expect(!request.enable)
        #expect(request.draft.identifier.rawValue == "new-service")
        #expect(state.editor == nil)
        #expect(state.selectedIdentifier?.rawValue == "new-service")
    }

    @Test
    func `cancelled import is silent and does not read any file`() async throws {
        let transfer = try TransferUseCaseStub(draft: makeDraft())
        let reducer = ServicesReducer(dependencies: .init(
            serviceManagementUseCase: TestServiceManagementUseCase(), serviceTransferUseCase: transfer,
            transferFilePanelClient: .init(chooseImportFile: { nil }, chooseExportFile: { _ in nil }),
        ))
        var state = ServicesState()
        let effect = reducer.reduce(into: &state, action: .transfer(.importService))
        _ = try reducer.reduce(into: &state, action: #require(await effect.executeForTesting()))
        #expect(state.editor == nil)
        #expect(state.failure == nil)
        #expect(state.canOpenEditor)
        #expect(await transfer.reads.isEmpty)
    }

    @Test
    func `invalid import stays on management screen with localized JSON error`() async throws {
        let error = ServiceJSONError.invalidDocument(reason: "service.kind: unknown value")
        let transfer = try TransferUseCaseStub(draft: makeDraft(), readError: error)
        let reducer = makeReducer(transfer: transfer)
        var state = ServicesState()
        let effect = reducer.reduce(into: &state, action: .transfer(.importService))
        _ = try reducer.reduce(into: &state, action: #require(await effect.executeForTesting()))
        #expect(state.editor == nil)
        #expect(state.transferOperation == nil)
        #expect(state.failure == .serviceJSON(error))
        #expect(state.failure?.localizedMessage == "\(L10n.Error.invalidServiceJSON)\nservice.kind: unknown value")
        #expect(ServicesFailure.from(error) == .serviceJSON(error))
    }

    @Test(arguments: [false, true])
    func `export keeps its original service even if selection changes and cancellation is silent`(
        cancel: Bool,
    ) async throws {
        let draft = try makeDraft()
        let transfer = TransferUseCaseStub(draft: draft)
        let panelRequests = ExportPanelRequests()
        let url = URL(filePath: "/tmp/export.json")
        let reducer = ServicesReducer(dependencies: .init(
            serviceManagementUseCase: TestServiceManagementUseCase(), serviceTransferUseCase: transfer,
            transferFilePanelClient: .init(chooseImportFile: { nil }, chooseExportFile: { identifier in
                await panelRequests.record(identifier)
                return cancel ? nil : url
            }),
        ))
        var state = ServicesState()
        state.services = [definition(draft)]
        let effect = reducer.reduce(into: &state, action: .transfer(.exportService(draft.identifier)))
        let duplicate = reducer.reduce(into: &state, action: .transfer(.exportService(draft.identifier)))
        #expect(await duplicate.executeForTesting() == nil)
        _ = try reducer.reduce(into: &state, action: .selectService(ServiceIdentifier("other")))
        _ = try reducer.reduce(into: &state, action: #require(await effect.executeForTesting()))
        #expect(await panelRequests.identifiers == [draft.identifier])
        #expect(await transfer.exports.count == (cancel ? 0 : 1))
        if !cancel {
            let exported = try #require(await transfer.exports.first)
            #expect(exported.identifier == draft.identifier)
            #expect(exported.url == url)
        }
        #expect(state.transferOperation == nil)
        #expect(state.failure == nil)
        #expect(state.editor == nil)
    }

    @Test
    func `export failures are shown and editor state cannot be replaced during transfer`() async throws {
        let draft = try makeDraft()
        let error = MoyError.fileOperation(path: "/tmp/export.json", reason: "write failed")
        let reducer = makeReducer(transfer: TransferUseCaseStub(draft: draft, exportError: error))
        var state = ServicesState()
        state.services = [definition(draft)]
        let effect = reducer.reduce(into: &state, action: .transfer(.exportService(draft.identifier)))
        _ = reducer.reduce(into: &state, action: .presentEditService(draft.identifier))
        #expect(state.editor == nil)
        _ = try reducer.reduce(into: &state, action: #require(await effect.executeForTesting()))
        #expect(state.failure == .moy(error))
        #expect(state.canOpenEditor)
        _ = reducer.reduce(into: &state, action: .presentCreateService)
        let editor = state.editor
        let importEffect = reducer.reduce(into: &state, action: .transfer(.importService))
        #expect(await importEffect.executeForTesting() == nil)
        #expect(state.editor === editor)
    }

    private func makeReducer(
        transfer: TransferUseCaseStub,
        management: TestServiceManagementUseCase = TestServiceManagementUseCase(),
    ) -> ServicesReducer {
        ServicesReducer(dependencies: .init(
            serviceManagementUseCase: management, serviceTransferUseCase: transfer,
            transferFilePanelClient: .init(
                chooseImportFile: { URL(filePath: "/tmp/import.json") },
                chooseExportFile: { _ in URL(filePath: "/tmp/export.json") },
            ),
        ))
    }

    private func makeDraft() throws -> ServiceDraft {
        try ServiceDraft(
            identifier: ServiceIdentifier("imported-service"),
            displayName: "Imported service", description: "Description",
            programArguments: ["/missing/tool", "", "hello world", "$PORT"], workingDirectory: "/tmp",
            environmentVariables: ["Z": "a=b", "A": "$VALUE"], runAtLoad: true, keepAlive: true,
            throttleInterval: 12, standardOutPath: nil, standardErrorPath: "/tmp/custom.stderr.log",
        )
    }

    private func definition(_ draft: ServiceDraft) -> ServiceDefinition {
        ServiceDefinition(
            identifier: draft.identifier, programArguments: draft.programArguments,
            standardOutPath: "/tmp/out", standardErrorPath: "/tmp/err",
        )
    }
}

private actor ExportPanelRequests {
    private(set) var identifiers: [ServiceIdentifier] = []
    func record(_ identifier: ServiceIdentifier) {
        identifiers.append(identifier)
    }
}

private actor TransferUseCaseStub: ServiceTransferUseCase {
    struct Export: Sendable {
        let identifier: ServiceIdentifier
        let url: URL
    }

    let draft: ServiceDraft
    let readError: ServiceJSONError?
    let exportError: MoyError?
    private(set) var reads: [URL] = []
    private(set) var exports: [Export] = []
    private(set) var importCalls = 0

    init(draft: ServiceDraft, readError: ServiceJSONError? = nil, exportError: MoyError? = nil) {
        self.draft = draft
        self.readError = readError
        self.exportError = exportError
    }

    func readService(from url: URL) async throws -> ServiceDraft {
        reads.append(url)
        if let readError {
            throw readError
        }
        return draft
    }

    func importService(from _: URL, enable _: Bool) async throws -> ServiceDefinition {
        importCalls += 1
        return ServiceDefinition(
            identifier: draft.identifier, programArguments: draft.programArguments,
            standardOutPath: "/tmp/out", standardErrorPath: "/tmp/err",
        )
    }

    func exportService(identifier: ServiceIdentifier, to url: URL) async throws {
        if let exportError {
            throw exportError
        }
        exports.append(Export(identifier: identifier, url: url))
    }
}
