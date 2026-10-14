import Foundation

extension ServiceEditorReducer {
    // swiftlint:disable:next cyclomatic_complexity
    func reduceArguments(into state: inout ServiceEditorState, action: ServiceEditorArgumentsAction) {
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
                let nextIndex = min(index, editor.arguments.count - 1)
                editor.selectedArgumentID = editor.arguments.isEmpty ? nil : editor.arguments[nextIndex].id
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
}
