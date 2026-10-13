import Foundation
import NanoRedux

struct ServiceEditorReducer: InjectableReducer {
    let dependencies: ServiceEditorDependencies

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func reduce(into state: inout ServiceEditorState, action: ServiceEditorAction) -> Effect<ServiceEditorAction> {
        switch action {
        case .cancel:
            guard !state.isSaving else { return .none }
            let id = state.id
            return .run { .delegate(.cancel(id)) }

        case .dismissFailure:
            state.failure = nil
            return .none

        case .saveService:
            guard !state.isSaving else { return .none }
            state.failure = nil
            do {
                let payload = try ServiceEditorPayload(editor: state)
                state.isSaving = true
                let id = state.id
                return .run { .delegate(.save(id, payload)) }
            } catch {
                state.failure = .from(error)
                return .none
            }

        case let .receiveSave(result):
            state.isSaving = false
            if case let .failure(failure) = result {
                state.failure = failure
            }
            return .none

        case .delegate:
            return .none

        case let .updateEditor(field):
            guard !state.isSaving else { return .none }
            let editor = state
            switch field {
            case let .identifier(value):
                guard case .create = editor.mode else { return .none }
                editor.identifier = value
            case let .displayName(value):
                editor.displayName = value
            case let .description(value):
                editor.serviceDescription = value
            case let .executable(value):
                editor.executable = value
            case let .workingDirectory(value):
                editor.workingDirectory = value
            case let .runAtLoad(value):
                editor.runAtLoad = value
            case let .keepAlive(value):
                editor.keepAlive = value
            case let .throttleInterval(value):
                editor.throttleInterval = value
            case let .standardOutPath(value):
                editor.standardOutPath = value
            case let .standardErrorPath(value):
                editor.standardErrorPath = value
            }
            return .none

        case .selectArgument, .moveArgument, .dropArgument, .addArgument, .updateArgument, .removeArgument,
             .selectEnvironmentVariable, .addEnvironmentVariable, .updateEnvironmentKey,
             .updateEnvironmentValue, .removeEnvironmentVariable:
            reduceEditorList(into: &state, action: action)
            return .none

        case let .chooseEditorPath(path):
            guard !state.isSaving else { return .none }
            let sessionID = state.id
            let filePanelClient = dependencies.filePanelClient
            return .run(lifetime: .replaceable("serviceEditor.choosePath")) {
                let selectedPath = await filePanelClient.choosePath(path)
                return .receiveEditorPath(sessionID, path, selectedPath)
            }

        case let .receiveEditorPath(sessionID, path, selectedPath):
            guard state.id == sessionID else { return .none }
            guard let selectedPath else { return .none }
            let field: ServiceEditorField = switch path {
            case .executable: .executable(selectedPath)
            case .workingDirectory: .workingDirectory(selectedPath)
            case .standardOut: .standardOutPath(selectedPath)
            case .standardError: .standardErrorPath(selectedPath)
            }
            return reduce(into: &state, action: .updateEditor(field))
        }
    }
}
