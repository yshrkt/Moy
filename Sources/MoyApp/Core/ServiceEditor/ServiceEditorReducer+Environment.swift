import Foundation

extension ServiceEditorReducer {
    // swiftlint:disable:next cyclomatic_complexity
    func reduceEnvironment(into state: inout ServiceEditorState, action: ServiceEditorEnvironmentAction) {
        guard !state.isSaving else { return }
        let editor = state
        switch action {
        case let .select(id):
            guard id == nil || editor.environmentVariables.contains(where: { $0.id == id }) else { return }
            editor.selectedEnvironmentVariableID = id

        case .add:
            let variable = ServiceEditorState.EnvironmentVariable()
            editor.environmentVariables.append(variable)
            editor.selectedEnvironmentVariableID = variable.id

        case let .updateKey(id, key):
            guard let index = editor.environmentVariables.firstIndex(where: { $0.id == id }) else { return }
            editor.environmentVariables[index].key = key

        case let .updateValue(id, value):
            guard let index = editor.environmentVariables.firstIndex(where: { $0.id == id }) else { return }
            editor.environmentVariables[index].value = value

        case let .remove(id):
            guard let index = editor.environmentVariables.firstIndex(where: { $0.id == id }) else { return }
            editor.environmentVariables.remove(at: index)
            if editor.selectedEnvironmentVariableID == id {
                let nextIndex = min(index, editor.environmentVariables.count - 1)
                editor.selectedEnvironmentVariableID = editor.environmentVariables.isEmpty
                    ? nil : editor.environmentVariables[nextIndex].id
            }
        }
    }
}
