import AppKit
@testable import MoyApp
import MoyKit
import NanoRedux
import SwiftUI
import Testing

@MainActor
@Suite("Service description editing", .serialized)
struct ServiceDescriptionEditorTests {
    @Test
    func `conversion in the middle preserves text and insertion point`() async throws {
        let state = ServicesState()
        state.editor = .create()
        let original = "先頭😀末尾"
        state.editor?.serviceDescription = original
        let store = Store.reducer(
            initialState: state,
            reducer: ServicesReducer(dependencies: ServicesDependencies(
                serviceManagementUseCase: TestServiceManagementUseCase(),
            )),
        )
        let editor = try #require(state.editor)
        let editorStore = store.scope(state: { _ in editor }, action: ServicesAction.editor)
        let host = NSHostingView(rootView: ServiceEditorView(store: editorStore))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 680),
            styleMask: [.titled], backing: .buffered, defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let textView = try #require(descriptionTextView(in: host))
        #expect(textView.string == original)
        window.makeFirstResponder(textView)
        let position = ("先頭😀" as NSString).length
        textView.setSelectedRange(NSRange(location: position, length: 0))
        textView.setMarkedText(
            "かな", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0),
        )
        try await Task.sleep(for: .milliseconds(100))
        #expect(textView.hasMarkedText())
        textView.insertText("仮名", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(for: .milliseconds(100))

        #expect(textView.string == "先頭😀仮名末尾")
        #expect(textView.selectedRange() == NSRange(location: position + 2, length: 0))
        #expect(state.editor?.serviceDescription == textView.string)
        // A subsequent character must be inserted at the same position, not at the end.
        textView.insertText("追加", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(for: .milliseconds(100))
        #expect(textView.string == "先頭😀仮名追加末尾")
        #expect(state.editor?.serviceDescription == textView.string)
    }

    private func descriptionTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView, !textView.isFieldEditor {
            return textView
        }
        for child in view.subviews {
            if let textView = descriptionTextView(in: child) {
                return textView
            }
        }
        return nil
    }
}
