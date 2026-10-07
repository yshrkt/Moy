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
                    behaviorSection(editor)
                    logsSection(editor)
                }
                .formStyle(.grouped)
                .textFieldStyle(.roundedBorder)
                .disabled(store.state.isSaving)
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
        .alert(
            L10n.Common.error,
            isPresented: Binding(
                get: { store.state.editor != nil && store.state.failure != nil },
                set: { isPresented in
                    if !isPresented {
                        store.send(.dismissFailure)
                    }
                },
            ),
        ) {
            Button(L10n.Common.ok) {
                store.send(.dismissFailure)
            }
        } message: {
            Text(store.state.failure?.localizedMessage ?? "")
        }
    }
}

private extension ServiceEditorView {
    private func identitySection(_ editor: ServiceEditorState) -> some View {
        Section {
            labelField(editor)
            LabeledContent(L10n.Services.displayName) {
                TextField(L10n.Services.displayName, text: fieldBinding(
                    value: editor.displayName,
                    field: ServiceEditorField.displayName,
                ))
                .labelsHidden()
            }
            .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Services.description)
                ServiceDescriptionEditor(value: editor.serviceDescription) { value in
                    store.send(.updateEditor(.description(value)))
                }
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(5)
                .frame(minHeight: 70)
                .background(.background, in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(.quaternary, lineWidth: 1)
                }
                .accessibilityLabel(L10n.Services.description)
            }
            .padding(.vertical, 4)
        } header: {
            Text(L10n.Services.identity)
        }
    }

    private func labelField(_ editor: ServiceEditorState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                Text("Label")
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(ServiceIdentifier.launchdLabelPrefix)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize()
                    TextField(L10n.Services.identifier, text: fieldBinding(
                        value: editor.identifier,
                        field: ServiceEditorField.identifier,
                    ))
                    .labelsHidden()
                    .accessibilityLabel(L10n.Services.identifier)
                    .frame(width: 120)
                    .disabled(isEditing(editor))
                }
                .font(.body.monospaced())
            }
            fieldHelp(L10n.Services.identifierHelp)
        }
        .padding(.vertical, 4)
    }

    private func commandSection(_ editor: ServiceEditorState) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("ProgramArguments")
                VStack(alignment: .leading, spacing: 12) {
                    PathField(
                        title: L10n.Services.executable,
                        labelFont: .callout,
                        isInline: true,
                        value: fieldBinding(value: editor.executable, field: ServiceEditorField.executable),
                    ) {
                        store.send(.chooseEditorPath(.executable))
                    }
                    ServiceArgumentsList(store: store, editor: editor)
                }
            }
            .padding(.vertical, 4)
            PathField(
                title: "WorkingDirectory",
                value: fieldBinding(
                    value: editor.workingDirectory,
                    field: ServiceEditorField.workingDirectory,
                ),
            ) {
                store.send(.chooseEditorPath(.workingDirectory))
            }
            .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 8) {
                Text("EnvironmentVariables")
                ServiceEnvironmentList(store: store, editor: editor)
            }
            .padding(.vertical, 4)
        } header: {
            Text(L10n.Services.executionSettings)
        }
    }

    private func behaviorSection(_ editor: ServiceEditorState) -> some View {
        Section {
            behaviorRow("RunAtLoad", help: L10n.Services.runAtLoadHelp) {
                behaviorToggle(
                    "RunAtLoad",
                    isOn: boolBinding(value: editor.runAtLoad, field: ServiceEditorField.runAtLoad),
                    help: L10n.Services.runAtLoad,
                )
            }
            behaviorRow("KeepAlive", help: L10n.Services.keepAliveHelp) {
                behaviorToggle(
                    "KeepAlive",
                    isOn: boolBinding(value: editor.keepAlive, field: ServiceEditorField.keepAlive),
                    help: L10n.Services.keepAlive,
                )
            }
            behaviorRow("ThrottleInterval", help: L10n.Services.throttleHelp) {
                HStack(spacing: 8) {
                    TextField(
                        "ThrottleInterval",
                        text: fieldBinding(
                            value: editor.throttleInterval,
                            field: ServiceEditorField.throttleInterval,
                        ),
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                    Text(L10n.Services.seconds)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L10n.Services.behavior)
        }
    }

    private func behaviorRow(
        _ title: String,
        help: String? = nil,
        @ViewBuilder control: () -> some View,
    ) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                if let help {
                    fieldHelp(help)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
                .fixedSize()
        }
        .padding(.vertical, 4)
    }

    private func behaviorToggle(_ title: String, isOn: Binding<Bool>, help: String) -> some View {
        Toggle(title, isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .fixedSize()
            .help(help)
    }

    private func logsSection(_ editor: ServiceEditorState) -> some View {
        Section {
            PathField(
                title: "StandardOutPath",
                placeholder: defaultLogPlaceholder(editor, standardError: false),
                value: fieldBinding(
                    value: editor.standardOutPath,
                    field: ServiceEditorField.standardOutPath,
                ),
            ) {
                store.send(.chooseEditorPath(.standardOut))
            }
            .padding(.vertical, 4)
            PathField(
                title: "StandardErrorPath",
                placeholder: defaultLogPlaceholder(editor, standardError: true),
                value: fieldBinding(
                    value: editor.standardErrorPath,
                    field: ServiceEditorField.standardErrorPath,
                ),
            ) {
                store.send(.chooseEditorPath(.standardError))
            }
            .padding(.vertical, 4)
            if case .create = editor.mode {
                fieldHelp(L10n.Services.defaultLogHelp)
                    .padding(.vertical, 4)
            }
        } header: {
            Text(L10n.Services.logs)
        } footer: {
            if case .edit = editor.mode {
                fieldHelp(L10n.Services.editReloadHelp)
            }
        }
    }

    private func defaultLogPlaceholder(_ editor: ServiceEditorState, standardError: Bool) -> String? {
        guard case .create = editor.mode else { return nil }
        let paths = MoyPaths.defaults()
        let identifier = try? ServiceIdentifier(editor.identifier)
        let url = standardError
            ? paths.standardErrorFilePreview(identifier: identifier)
            : paths.standardOutFilePreview(identifier: identifier)
        return url.path
    }

    private func fieldHelp(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
    var labelFont: Font = .body
    var isInline = false
    var placeholder: String?
    @Binding var value: String
    let choose: () -> Void

    var body: some View {
        if isInline {
            HStack(spacing: 8) {
                Text(title)
                    .font(labelFont)
                    .fixedSize()
                pathInput
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(labelFont)
                pathInput
            }
        }
    }

    private var pathInput: some View {
        HStack(spacing: 8) {
            TextField(title, text: $value, prompt: placeholder.map { Text($0) })
                .labelsHidden()
                .font(.body.monospaced())
                .frame(maxWidth: .infinity)
            Button(L10n.Common.choose, action: choose)
                .fixedSize()
        }
    }
}
