import NanoRedux
import SwiftUI

struct ServiceArgumentsList: View {
    let store: ServiceEditorStore
    let editor: ServiceEditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ServiceEditorList(
                columns: [L10n.Services.argument],
                rows: editor.arguments.map { .init(id: $0.id, values: [$0.value]) },
                selection: editor.selectedArgumentID,
                emptyMessage: L10n.Services.noArguments,
                addLabel: L10n.Services.addArgument,
                removeLabel: L10n.Services.removeArgument,
                select: { store.send(.selectArgument($0)) },
                update: { id, _, value in store.send(.updateArgument(id, value)) },
                add: { store.send(.addArgument) },
                remove: { store.send(.removeArgument($0)) },
                move: { store.send(.moveArgument($0, toIndex: $1)) },
                drop: { store.send(.dropArgument($0, insertionIndex: $1)) },
            )
            Text(L10n.Services.argumentsHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(store.state.isSaving)
    }
}
