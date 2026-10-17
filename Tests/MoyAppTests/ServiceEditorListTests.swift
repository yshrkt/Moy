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
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.add)))
        let first = try #require(state.editor?.selectedArgumentID)
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.update(first, "first"))))
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.add)))
        let last = try #require(state.editor?.selectedArgumentID)
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.select(first))))
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.add)))
        let middle = try #require(state.editor?.selectedArgumentID)
        #expect(state.editor?.arguments.map(\.id) == [first, middle, last])

        _ = reducer.reduce(into: &state, action: .editor(.arguments(.move(first, toIndex: 2))))
        #expect(state.editor?.arguments.map(\.id) == [middle, last, first])
        #expect(state.editor?.arguments.last?.value == "first")
        #expect(state.editor?.selectedArgumentID == first)
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.move(first, toIndex: 0))))
        #expect(state.editor?.arguments.map(\.id) == [first, middle, last])

        _ = reducer.reduce(into: &state, action: .editor(.arguments(.select(nil))))
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.add)))
        #expect(state.editor?.arguments.prefix(3).map(\.id) == [first, middle, last])
        #expect(state.editor?.arguments.last?.id == state.editor?.selectedArgumentID)
    }

    @Test
    func `deleting selection chooses next then previous then nothing`() throws {
        let reducer = makeReducer()
        var state = ServicesState()
        state.editor = .create()
        for _ in 0 ..< 3 {
            _ = reducer.reduce(into: &state, action: .editor(.arguments(.add)))
        }
        let ids = try #require(state.editor?.arguments.map(\.id))
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.select(ids[1]))))
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.remove(ids[1]))))
        #expect(state.editor?.selectedArgumentID == ids[2])
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.remove(ids[2]))))
        #expect(state.editor?.selectedArgumentID == ids[0])
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.remove(ids[0]))))
        #expect(state.editor?.selectedArgumentID == nil)
        #expect(state.editor?.arguments.isEmpty == true)
    }

    @Test
    func `out of bounds moves and stale row actions do nothing`() throws {
        let reducer = makeReducer()
        var state = ServicesState()
        state.editor = .create()
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.add)))
        let id = try #require(state.editor?.selectedArgumentID)
        let editor = try #require(state.editor)
        let arguments = editor.arguments
        let environment = editor.environmentVariables
        let selectedArgument = editor.selectedArgumentID
        let selectedEnvironment = editor.selectedEnvironmentVariableID
        let stale = UUID()
        let actions: [ServiceEditorAction] = [
            .arguments(.move(id, toIndex: -1)),
            .arguments(.move(id, toIndex: 1)),
            .arguments(.move(id, toIndex: 0)),
            .arguments(.move(stale, toIndex: 0)),
            .arguments(.drop(id, insertionIndex: -1)),
            .arguments(.drop(id, insertionIndex: 2)),
            .arguments(.drop(stale, insertionIndex: 0)),
            .arguments(.select(stale)),
            .arguments(.remove(stale)),
            .arguments(.update(stale, "lost")),
            .environment(.select(stale)),
            .environment(.remove(stale)),
            .environment(.updateKey(stale, "lost")),
            .environment(.updateValue(stale, "lost")),
        ]
        for action in actions {
            _ = reducer.reduce(into: &state, action: .editor(action))
            #expect(editor.arguments == arguments)
            #expect(editor.environmentVariables == environment)
            #expect(editor.selectedArgumentID == selectedArgument)
            #expect(editor.selectedEnvironmentVariableID == selectedEnvironment)
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
            _ = reducer.reduce(into: &state, action: .editor(.arguments(.add)))
        }
        let original = try #require(state.editor?.arguments)
        let dragged = original[scenario.source].id
        _ = reducer.reduce(
            into: &state,
            action: .editor(.arguments(.drop(dragged, insertionIndex: scenario.insertion))),
        )
        #expect(state.editor?.arguments == scenario.expected.map { original[$0] })
        #expect(state.editor?.selectedArgumentID == dragged)
    }

    @Test
    func `environment additions append and editing does not sort rows`() throws {
        let reducer = makeReducer()
        var state = ServicesState()
        state.editor = .create()
        _ = reducer.reduce(into: &state, action: .editor(.environment(.add)))
        let first = try #require(state.editor?.selectedEnvironmentVariableID)
        _ = reducer.reduce(into: &state, action: .editor(.environment(.updateKey(first, "Z"))))
        _ = reducer.reduce(into: &state, action: .editor(.environment(.add)))
        let second = try #require(state.editor?.selectedEnvironmentVariableID)
        _ = reducer.reduce(into: &state, action: .editor(.environment(.updateKey(second, "A"))))
        _ = reducer.reduce(into: &state, action: .editor(.environment(.select(first))))
        _ = reducer.reduce(into: &state, action: .editor(.environment(.add)))
        let third = try #require(state.editor?.selectedEnvironmentVariableID)
        #expect(state.editor?.environmentVariables.map(\.id) == [first, second, third])
        _ = reducer.reduce(into: &state, action: .editor(.environment(.select(second))))
        _ = reducer.reduce(into: &state, action: .editor(.environment(.remove(second))))
        #expect(state.editor?.selectedEnvironmentVariableID == third)
        _ = reducer.reduce(into: &state, action: .editor(.environment(.remove(third))))
        #expect(state.editor?.selectedEnvironmentVariableID == first)
        _ = reducer.reduce(into: &state, action: .editor(.environment(.remove(first))))
        #expect(state.editor?.selectedEnvironmentVariableID == nil)
    }

    @Test
    func `saving blocks every list action`() throws {
        let reducer = makeReducer()
        var state = ServicesState()
        state.editor = .create()
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.add)))
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.add)))
        _ = reducer.reduce(into: &state, action: .editor(.environment(.add)))
        let argument = try #require(state.editor?.selectedArgumentID)
        let variable = try #require(state.editor?.selectedEnvironmentVariableID)
        state.editor?.isSaving = true
        let editor = try #require(state.editor)
        let arguments = editor.arguments
        let environment = editor.environmentVariables
        let selectedArgument = editor.selectedArgumentID
        let selectedEnvironment = editor.selectedEnvironmentVariableID
        let actions: [ServiceEditorAction] = [
            .arguments(.select(nil)),
            .arguments(.add),
            .arguments(.update(argument, "changed")),
            .arguments(.remove(argument)),
            .arguments(.move(argument, toIndex: 0)),
            .arguments(.drop(argument, insertionIndex: 0)),
            .environment(.select(nil)),
            .environment(.add),
            .environment(.updateKey(variable, "changed")),
            .environment(.updateValue(variable, "changed")),
            .environment(.remove(variable)),
        ]
        for action in actions {
            _ = reducer.reduce(into: &state, action: .editor(action))
            #expect(editor.arguments == arguments)
            #expect(editor.environmentVariables == environment)
            #expect(editor.selectedArgumentID == selectedArgument)
            #expect(editor.selectedEnvironmentVariableID == selectedEnvironment)
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
        _ = reducer.reduce(into: &state, action: .editor(.arguments(.move(last, toIndex: 0))))
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
            editor: ServiceEditorDependencies(filePanelClient: FilePanelClient(choosePath: { _ in nil })),
            workspaceClient: WorkspaceClient(open: { _ in }, reveal: { _ in }),
        ))
    }
}
