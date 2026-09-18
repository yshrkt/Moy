import Foundation
@testable import MoyApp
import MoyKit
import NanoRedux
import Testing

@Suite("Service editor lists")
struct ServiceEditorListTests {
    @Test
    func `insert after selection or append and retain row identities when moving`() throws {
        let reducer = makeReducer()
        var state = ServicesState()
        _ = reducer.reduce(into: &state, action: .presentCreateService)
        _ = reducer.reduce(into: &state, action: .addArgument)
        let first = try #require(state.editor?.selectedArgumentID)
        _ = reducer.reduce(into: &state, action: .updateArgument(first, "first"))
        _ = reducer.reduce(into: &state, action: .addArgument)
        let last = try #require(state.editor?.selectedArgumentID)
        _ = reducer.reduce(into: &state, action: .selectArgument(first))
        _ = reducer.reduce(into: &state, action: .addArgument)
        let middle = try #require(state.editor?.selectedArgumentID)
        #expect(state.editor?.arguments.map(\.id) == [first, middle, last])

        _ = reducer.reduce(into: &state, action: .moveArgument(first, toIndex: 2))
        #expect(state.editor?.arguments.map(\.id) == [middle, last, first])
        #expect(state.editor?.arguments.last?.value == "first")
        #expect(state.editor?.selectedArgumentID == first)
        _ = reducer.reduce(into: &state, action: .moveArgument(first, toIndex: 0))
        #expect(state.editor?.arguments.map(\.id) == [first, middle, last])

        _ = reducer.reduce(into: &state, action: .selectArgument(nil))
        _ = reducer.reduce(into: &state, action: .addArgument)
        #expect(state.editor?.arguments.prefix(3).map(\.id) == [first, middle, last])
        #expect(state.editor?.arguments.last?.id == state.editor?.selectedArgumentID)
    }

    @Test
    func `deleting selection chooses next then previous then nothing`() throws {
        let reducer = makeReducer()
        var state = ServicesState()
        state.editor = .create()
        for _ in 0 ..< 3 {
            _ = reducer.reduce(into: &state, action: .addArgument)
        }
        let ids = try #require(state.editor?.arguments.map(\.id))
        _ = reducer.reduce(into: &state, action: .selectArgument(ids[1]))
        _ = reducer.reduce(into: &state, action: .removeArgument(ids[1]))
        #expect(state.editor?.selectedArgumentID == ids[2])
        _ = reducer.reduce(into: &state, action: .removeArgument(ids[2]))
        #expect(state.editor?.selectedArgumentID == ids[0])
        _ = reducer.reduce(into: &state, action: .removeArgument(ids[0]))
        #expect(state.editor?.selectedArgumentID == nil)
        #expect(state.editor?.arguments.isEmpty == true)
    }

    @Test
    func `out of bounds moves and stale row actions do nothing`() throws {
        let reducer = makeReducer()
        var state = ServicesState()
        state.editor = .create()
        _ = reducer.reduce(into: &state, action: .addArgument)
        let id = try #require(state.editor?.selectedArgumentID)
        let original = state.editor
        let stale = UUID()
        let actions: [ServicesAction] = [
            .moveArgument(id, toIndex: -1), .moveArgument(id, toIndex: 1),
            .moveArgument(id, toIndex: 0), .moveArgument(stale, toIndex: 0),
            .dropArgument(id, insertionIndex: -1), .dropArgument(id, insertionIndex: 2),
            .dropArgument(stale, insertionIndex: 0),
            .selectArgument(stale), .removeArgument(stale), .updateArgument(stale, "lost"),
            .selectEnvironmentVariable(stale), .removeEnvironmentVariable(stale),
            .updateEnvironmentKey(stale, "lost"), .updateEnvironmentValue(stale, "lost"),
        ]
        for action in actions {
            _ = reducer.reduce(into: &state, action: action)
            #expect(state.editor == original)
        }
    }

    struct DropScenario: Sendable {
        let source: Int
        let insertion: Int
        let expected: [Int]
    }

    @Test(arguments: [
        DropScenario(source: 0, insertion: 3, expected: [1, 2, 0]),
        DropScenario(source: 2, insertion: 0, expected: [2, 0, 1]),
        DropScenario(source: 0, insertion: 2, expected: [1, 0, 2]),
        DropScenario(source: 2, insertion: 1, expected: [0, 2, 1]),
        DropScenario(source: 1, insertion: 1, expected: [0, 1, 2]),
        DropScenario(source: 1, insertion: 2, expected: [0, 1, 2]),
    ])
    func `table drop insertion preserves order identities and selection`(
        scenario: DropScenario,
    ) throws {
        let reducer = makeReducer()
        var state = ServicesState()
        state.editor = .create()
        for _ in 0 ..< 3 {
            _ = reducer.reduce(into: &state, action: .addArgument)
        }
        let original = try #require(state.editor?.arguments)
        let dragged = original[scenario.source].id
        _ = reducer.reduce(into: &state, action: .dropArgument(dragged, insertionIndex: scenario.insertion))
        #expect(state.editor?.arguments == scenario.expected.map { original[$0] })
        #expect(state.editor?.selectedArgumentID == dragged)
    }

    @Test
    func `environment additions append and editing does not sort rows`() throws {
        let reducer = makeReducer()
        var state = ServicesState()
        state.editor = .create()
        _ = reducer.reduce(into: &state, action: .addEnvironmentVariable)
        let first = try #require(state.editor?.selectedEnvironmentVariableID)
        _ = reducer.reduce(into: &state, action: .updateEnvironmentKey(first, "Z"))
        _ = reducer.reduce(into: &state, action: .addEnvironmentVariable)
        let second = try #require(state.editor?.selectedEnvironmentVariableID)
        _ = reducer.reduce(into: &state, action: .updateEnvironmentKey(second, "A"))
        _ = reducer.reduce(into: &state, action: .selectEnvironmentVariable(first))
        _ = reducer.reduce(into: &state, action: .addEnvironmentVariable)
        let third = try #require(state.editor?.selectedEnvironmentVariableID)
        #expect(state.editor?.environmentVariables.map(\.id) == [first, second, third])
        _ = reducer.reduce(into: &state, action: .selectEnvironmentVariable(second))
        _ = reducer.reduce(into: &state, action: .removeEnvironmentVariable(second))
        #expect(state.editor?.selectedEnvironmentVariableID == third)
        _ = reducer.reduce(into: &state, action: .removeEnvironmentVariable(third))
        #expect(state.editor?.selectedEnvironmentVariableID == first)
        _ = reducer.reduce(into: &state, action: .removeEnvironmentVariable(first))
        #expect(state.editor?.selectedEnvironmentVariableID == nil)
    }

    @Test
    func `saving blocks every list action`() throws {
        let reducer = makeReducer()
        var state = ServicesState()
        state.editor = .create()
        _ = reducer.reduce(into: &state, action: .addArgument)
        _ = reducer.reduce(into: &state, action: .addArgument)
        _ = reducer.reduce(into: &state, action: .addEnvironmentVariable)
        let argument = try #require(state.editor?.selectedArgumentID)
        let variable = try #require(state.editor?.selectedEnvironmentVariableID)
        state.isSaving = true
        let original = state.editor
        let actions: [ServicesAction] = [
            .selectArgument(nil), .addArgument, .updateArgument(argument, "changed"),
            .removeArgument(argument), .moveArgument(argument, toIndex: 0), .dropArgument(argument, insertionIndex: 0),
            .selectEnvironmentVariable(nil), .addEnvironmentVariable,
            .updateEnvironmentKey(variable, "changed"), .updateEnvironmentValue(variable, "changed"),
            .removeEnvironmentVariable(variable),
        ]
        for action in actions {
            _ = reducer.reduce(into: &state, action: action)
            #expect(state.editor == original)
        }
    }

    @Test
    func `saved arguments stay literal and ordered and environment reopens sorted`() throws {
        let values = ["", "  spaces  ", "\"quoted\"", "$PORT", "${PORT}", "a\nb", "--port=3000"]
        let service = try ServiceDefinition(
            identifier: ServiceIdentifier("list-test"),
            programArguments: ["/usr/bin/true"] + values,
            environmentVariables: ["Z": "  preserved  ", "A": "$Z"],
            standardOutPath: "/tmp/list.out", standardErrorPath: "/tmp/list.err",
        )
        var state = ServicesState()
        state.editor = ServiceEditorState(service: service)
        let reducer = makeReducer()
        let last = try #require(state.editor?.arguments.last?.id)
        _ = reducer.reduce(into: &state, action: .moveArgument(last, toIndex: 0))
        let editor = try #require(state.editor)
        guard case let .update(saved) = try ServiceEditorPayload(editor: editor) else {
            Issue.record("Expected an update payload")
            return
        }
        let decoded = try JSONDecoder().decode(ServiceDefinition.self, from: JSONEncoder().encode(saved))
        let reopened = ServiceEditorState(service: decoded)
        #expect(try reopened.arguments.map(\.value) == [#require(values.last)] + values.dropLast())
        #expect(decoded.programArguments.first == "/usr/bin/true")
        #expect(reopened.environmentVariables.map(\.key) == ["A", "Z"])
        #expect(decoded.environmentVariables == service.environmentVariables)
        #expect(reopened.selectedArgumentID == nil)
        #expect(reopened.selectedEnvironmentVariableID == nil)
    }

    @Test
    func `environment validation still rejects empty and duplicate names`() throws {
        var editor = ServiceEditorState.create()
        editor.identifier = "list-test"
        editor.executable = "/usr/bin/true"
        editor.environmentVariables = [.init(key: " ", value: "")]
        #expect(throws: ServicesFailure.emptyEnvironmentKey) { try ServiceEditorPayload(editor: editor) }
        editor.environmentVariables = [.init(key: "PORT", value: "1"), .init(key: " PORT ", value: "2")]
        #expect(throws: ServicesFailure.duplicateEnvironmentKey("PORT")) { try ServiceEditorPayload(editor: editor) }
    }

    private func makeReducer() -> ServicesReducer {
        ServicesReducer(dependencies: ServicesDependencies(
            serviceManagementUseCase: TestServiceManagementUseCase(),
            filePanelClient: FilePanelClient(choosePath: { _ in nil }),
            workspaceClient: WorkspaceClient(open: { _ in }, reveal: { _ in }),
        ))
    }
}
