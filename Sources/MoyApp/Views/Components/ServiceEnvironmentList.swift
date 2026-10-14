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
            select: { store.send(.environment(.selectEnvironmentVariable($0))) },
            update: { id, column, value in
                let action: ServiceEditorEnvironmentAction = column == 0
                    ? .updateEnvironmentKey(id, value) : .updateEnvironmentValue(id, value)
                store.send(.environment(action))
            },
            add: { store.send(.environment(.addEnvironmentVariable)) },
            remove: { store.send(.environment(.removeEnvironmentVariable($0))) },
        )
        .disabled(store.state.isSaving)
    }
}
