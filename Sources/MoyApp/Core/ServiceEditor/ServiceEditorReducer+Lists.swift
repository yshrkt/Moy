import Foundation

extension ServiceEditorReducer {
    // All list mutations share the saving guard and preserve stable row identities.
    // swiftlint:disable:next cyclomatic_complexity
    func reduceEditorList(into state: inout ServiceEditorState, action: ServiceEditorAction) {
        guard !state.isSaving else { return }
        let editor = state
        switch action {
        case let .selectArgument(id):
            guard id == nil || editor.arguments.contains(where: { $0.id == id }) else { return }
            editor.selectedArgumentID = id

        case .addArgument:
            let argument = ServiceEditorState.Argument()
            let index = editor.arguments.firstIndex { $0.id == editor.selectedArgumentID }
            editor.arguments.insert(argument, at: index.map { $0 + 1 } ?? editor.arguments.count)
            editor.selectedArgumentID = argument.id

        case let .updateArgument(id, value):
            guard let index = editor.arguments.firstIndex(where: { $0.id == id }) else { return }
            editor.arguments[index].value = value

        case let .removeArgument(id):
            guard let index = editor.arguments.firstIndex(where: { $0.id == id }) else { return }
            editor.arguments.remove(at: index)
            if editor.selectedArgumentID == id {
                editor.selectedArgumentID = neighborID(in: editor.arguments, removedAt: index)
            }

        case let .moveArgument(id, destination):
            moveArgument(in: editor, id: id, destination: destination)

        case let .dropArgument(id, insertion):
            guard (0 ... editor.arguments.count).contains(insertion),
                  let source = editor.arguments.firstIndex(where: { $0.id == id })
            else { return }
            // Table reports an insertion boundary before removing the dragged row.
            let destination = insertion > source ? insertion - 1 : insertion
            moveArgument(in: editor, id: id, destination: destination)

        case let .selectEnvironmentVariable(id):
            guard id == nil || editor.environmentVariables.contains(where: { $0.id == id }) else { return }
            editor.selectedEnvironmentVariableID = id

        case .addEnvironmentVariable:
            let variable = ServiceEditorState.EnvironmentVariable()
            editor.environmentVariables.append(variable)
            editor.selectedEnvironmentVariableID = variable.id

        case let .updateEnvironmentKey(id, key):
            guard let index = editor.environmentVariables.firstIndex(where: { $0.id == id }) else { return }
            editor.environmentVariables[index].key = key

        case let .updateEnvironmentValue(id, value):
            guard let index = editor.environmentVariables.firstIndex(where: { $0.id == id }) else { return }
            editor.environmentVariables[index].value = value

        case let .removeEnvironmentVariable(id):
            guard let index = editor.environmentVariables.firstIndex(where: { $0.id == id }) else { return }
            editor.environmentVariables.remove(at: index)
            if editor.selectedEnvironmentVariableID == id {
                editor.selectedEnvironmentVariableID = neighborID(in: editor.environmentVariables, removedAt: index)
            }

        default:
            return
        }
    }

    private func moveArgument(in editor: ServiceEditorState, id: UUID, destination: Int) {
        guard editor.arguments.indices.contains(destination),
              let source = editor.arguments.firstIndex(where: { $0.id == id })
        else { return }
        let argument = editor.arguments.remove(at: source)
        editor.arguments.insert(argument, at: destination)
        editor.selectedArgumentID = id
    }

    private func neighborID(in rows: [some Identifiable<UUID>], removedAt index: Int) -> UUID? {
        guard !rows.isEmpty else { return nil }
        return rows[min(index, rows.count - 1)].id
    }
}
