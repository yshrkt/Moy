import SwiftUI

/// Keep the native editor's binding synchronous while Store actions are processed asynchronously.
struct ServiceDescriptionEditor: View {
    @State private var text: String

    let update: (String) -> Void

    init(value: String, update: @escaping (String) -> Void) {
        _text = State(initialValue: value)
        self.update = update
    }

    var body: some View {
        TextEditor(text: $text)
            .onChange(of: text) { _, value in
                update(value)
            }
    }
}
