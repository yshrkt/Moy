import NanoRedux
import SwiftUI

struct ServiceEnvironmentList: View {
    let store: ServiceEditorStore
    let editor: ServiceEditorState

    var body: some View {
        ServiceEditorList(
            columns: [L10n.Services.environmentKey, L10n.Services.environmentValue],
            rows: editor.environmentVariables.map { .init(id: $0.id, values: [$0.key, $0.value]) },
            selection: editor.selectedEnvironmentVariableID,
            emptyMessage: L10n.Services.noEnvironmentVariables,
            addLabel: L10n.Services.addEnvironment,
            removeLabel: L10n.Services.removeEnvironment,
            select: { store.send(.selectEnvironmentVariable($0)) },
            update: { id, column, value in
                store.send(column == 0 ? .updateEnvironmentKey(id, value) : .updateEnvironmentValue(id, value))
            },
            add: { store.send(.addEnvironmentVariable) },
            remove: { store.send(.removeEnvironmentVariable($0)) },
        )
        .disabled(store.state.isSaving)
    }
}
