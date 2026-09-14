import MoyKit
import NanoRedux
import SwiftUI

@MainActor
struct ServiceEditorView: View {
    let store: ServicesStore

    var body: some View {
        NavigationStack {
            if let editor = store.state.editor {
                Form {
                    identitySection(editor)
                    commandSection(editor)
                    environmentSection(editor)
                    behaviorSection(editor)
                    logsSection(editor)

                    if case .edit = editor.mode {
                        Section {
                            Text(L10n.Services.editReloadHelp)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(editorTitle(editor))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.Common.cancel) {
                            store.send(.dismissEditor)
                        }
                        .disabled(store.state.isSaving)
                    }
                    ToolbarItemGroup(placement: .confirmationAction) {
                        if case .create = editor.mode {
                            Button(L10n.Common.save) {
                                store.send(.saveService(enable: false))
                            }
                            .disabled(!canSave(editor))
                            Button(L10n.Common.saveAndEnable) {
                                store.send(.saveService(enable: true))
                            }
                            .disabled(!canSave(editor))
                        } else {
                            Button(L10n.Common.save) {
                                store.send(.saveService(enable: false))
                            }
                            .disabled(!canSave(editor))
                        }
                    }
                }
                .overlay {
                    if store.state.isSaving {
                        ProgressView()
                            .controlSize(.large)
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .frame(minWidth: 680, minHeight: 680)
    }
}

private extension ServiceEditorView {
    private func identitySection(_ editor: ServiceEditorState) -> some View {
        Section {
            TextField(L10n.Services.identifier, text: fieldBinding(
                value: editor.identifier,
                field: ServiceEditorField.identifier,
            ))
            .disabled(isEditing(editor))
            Text(L10n.Services.identifierHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !editor.identifier.isEmpty {
                LabeledContent(L10n.Services.label) {
                    Text("\(ServiceIdentifier.launchdLabelPrefix)\(editor.identifier)")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            TextField(L10n.Services.displayName, text: fieldBinding(
                value: editor.displayName,
                field: ServiceEditorField.displayName,
            ))
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.Services.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: fieldBinding(
                    value: editor.serviceDescription,
                    field: ServiceEditorField.description,
                ))
                .frame(minHeight: 58)
            }
        } header: {
            Text(L10n.Services.identity)
        }
    }

    private func commandSection(_ editor: ServiceEditorState) -> some View {
        Section {
            PathField(
                title: L10n.Services.executable,
                value: fieldBinding(value: editor.executable, field: ServiceEditorField.executable),
            ) {
                store.send(.chooseEditorPath(.executable))
            }

            ForEach(editor.arguments) { argument in
                HStack {
                    TextField(
                        L10n.Services.argument,
                        text: Binding(
                            get: { argumentValue(argument.id) },
                            set: { store.send(.updateArgument(argument.id, $0)) },
                        ),
                    )
                    Button(role: .destructive) {
                        store.send(.removeArgument(argument.id))
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.Common.remove)
                    .accessibilityLabel(L10n.Common.remove)
                }
            }

            Button {
                store.send(.addArgument)
            } label: {
                Label(L10n.Services.addArgument, systemImage: "plus")
            }

            PathField(
                title: L10n.Services.workingDirectory,
                value: fieldBinding(
                    value: editor.workingDirectory,
                    field: ServiceEditorField.workingDirectory,
                ),
            ) {
                store.send(.chooseEditorPath(.workingDirectory))
            }
        } header: {
            Text(L10n.Services.configuration)
        }
    }

    private func environmentSection(_ editor: ServiceEditorState) -> some View {
        Section {
            ForEach(editor.environmentVariables) { variable in
                HStack {
                    TextField(
                        L10n.Services.environmentKey,
                        text: Binding(
                            get: { environmentKey(variable.id) },
                            set: { store.send(.updateEnvironmentKey(variable.id, $0)) },
                        ),
                    )
                    TextField(
                        L10n.Services.environmentValue,
                        text: Binding(
                            get: { environmentValue(variable.id) },
                            set: { store.send(.updateEnvironmentValue(variable.id, $0)) },
                        ),
                    )
                    Button(role: .destructive) {
                        store.send(.removeEnvironmentVariable(variable.id))
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.Common.remove)
                    .accessibilityLabel(L10n.Common.remove)
                }
            }

            Button {
                store.send(.addEnvironmentVariable)
            } label: {
                Label(L10n.Services.addEnvironment, systemImage: "plus")
            }
        } header: {
            Text(L10n.Services.environment)
        }
    }

    private func behaviorSection(_ editor: ServiceEditorState) -> some View {
        Section {
            Toggle(
                L10n.Services.runAtLoad,
                isOn: boolBinding(value: editor.runAtLoad, field: ServiceEditorField.runAtLoad),
            )
            Toggle(
                L10n.Services.keepAlive,
                isOn: boolBinding(value: editor.keepAlive, field: ServiceEditorField.keepAlive),
            )
            Text(L10n.Services.keepAliveHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField(
                    L10n.Services.throttleInterval,
                    text: fieldBinding(
                        value: editor.throttleInterval,
                        field: ServiceEditorField.throttleInterval,
                    ),
                )
                .frame(maxWidth: 160)
                Text(L10n.Services.seconds)
                    .foregroundStyle(.secondary)
            }
            Text(L10n.Services.throttleHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(L10n.Services.behavior)
        }
    }

    private func logsSection(_ editor: ServiceEditorState) -> some View {
        Section {
            PathField(
                title: L10n.Services.standardOut,
                value: fieldBinding(
                    value: editor.standardOutPath,
                    field: ServiceEditorField.standardOutPath,
                ),
            ) {
                store.send(.chooseEditorPath(.standardOut))
            }
            PathField(
                title: L10n.Services.standardError,
                value: fieldBinding(
                    value: editor.standardErrorPath,
                    field: ServiceEditorField.standardErrorPath,
                ),
            ) {
                store.send(.chooseEditorPath(.standardError))
            }
            if case .create = editor.mode {
                Text(L10n.Services.defaultLogHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(L10n.Services.logs)
        }
    }

    private func fieldBinding(
        value: String,
        field: @escaping @Sendable (String) -> ServiceEditorField,
    ) -> Binding<String> {
        Binding(
            get: { value },
            set: { store.send(.updateEditor(field($0))) },
        )
    }

    private func boolBinding(
        value: Bool,
        field: @escaping @Sendable (Bool) -> ServiceEditorField,
    ) -> Binding<Bool> {
        Binding(
            get: { value },
            set: { store.send(.updateEditor(field($0))) },
        )
    }

    private func argumentValue(_ id: UUID) -> String {
        store.state.editor?.arguments.first(where: { $0.id == id })?.value ?? ""
    }

    private func environmentKey(_ id: UUID) -> String {
        store.state.editor?.environmentVariables.first(where: { $0.id == id })?.key ?? ""
    }

    private func environmentValue(_ id: UUID) -> String {
        store.state.editor?.environmentVariables.first(where: { $0.id == id })?.value ?? ""
    }

    private func editorTitle(_ editor: ServiceEditorState) -> String {
        switch editor.mode {
        case .create: L10n.Services.newTitle
        case .edit: L10n.Services.editTitle
        }
    }

    private func isEditing(_ editor: ServiceEditorState) -> Bool {
        if case .edit = editor.mode {
            return true
        }
        return false
    }

    private func canSave(_ editor: ServiceEditorState) -> Bool {
        !store.state.isSaving
            && !editor.identifier.isEmpty
            && !editor.executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct PathField: View {
    let title: String
    @Binding var value: String
    let choose: () -> Void

    var body: some View {
        HStack {
            TextField(title, text: $value)
            Button(L10n.Common.choose, action: choose)
        }
    }
}
