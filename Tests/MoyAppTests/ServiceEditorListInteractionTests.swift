import AppKit
@testable import MoyApp
import Observation
import SwiftUI
import Testing

@MainActor
@Suite("Service editor table interaction", .serialized)
struct ServiceEditorListInteractionTests {
    @Test(arguments: [1, 6, 20, 60])
    func `table exposes every row and a row drag source inside a form`(rowCount: Int) async throws {
        let rows = (0 ..< rowCount).map { index in
            ServiceEditorList.Row(id: UUID(), values: ["argument-\(index)"])
        }
        let model = InteractionModel()
        let content = Form {
            Section {
                ServiceEditorList(
                    columns: ["Argument"], rows: rows, selection: model.selection,
                    emptyMessage: "No Arguments", addLabel: "Add", removeLabel: "Remove",
                    select: { model.selection = $0 }, update: { _, _, _ in }, add: {}, remove: { _ in },
                    move: { _, _ in }, drop: { _, _ in },
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 680, height: 420)
        let (host, window) = host(content)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()

        let table = try #require(descendant(of: host, type: NSTableView.self))
        let scroll = try #require(table.enclosingScrollView)
        #expect(table.numberOfRows == rows.count)
        #expect(scroll.contentView.bounds.contains(table.rect(ofRow: rows.count - 1)))
        // Fields stay mounted to make focus reliable, but mounting them must not
        // select or start editing the final row when the editor first appears.
        #expect(descendant(of: table, type: NSTextField.self) != nil)
        #expect(model.selection == nil)
        #expect(!(window.firstResponder is NSTextView))
        let outline = try #require(table as? NSOutlineView)
        let dataSource = try #require(outline.dataSource)
        let item = try #require(outline.item(atRow: 0))

        let writer = try #require(dataSource.outlineView?(outline, pasteboardWriterForItem: item))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        #expect(writer.writableTypes(for: pasteboard).contains(
            NSPasteboard.PasteboardType("com.sputnik-apps.moy.editor-argument"),
        ))

        table.selectRowIndexes(IndexSet(integer: rowCount - 1), byExtendingSelection: false)
        try await Task.sleep(for: .milliseconds(10))
        #expect(model.selection == rows.last?.id)
    }

    private func host<Content: View>(_ content: Content) -> (NSHostingView<Content>, NSWindow) {
        let host = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 420),
            styleMask: [.titled], backing: .buffered, defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        return (host, window)
    }

    @Test
    func `adding a row focuses and selects its first cell`() async throws {
        let model = MutableInteractionModel()
        let (host, window) = host(MutableInteractionList(model: model))
        defer { window.close() }
        host.layoutSubtreeIfNeeded()

        let added = UUID()
        model.rows.append(ServiceEditorList.Row(id: added, values: [""]))
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()

        #expect(model.selection == added)
    }

    private func descendant<T: NSView>(of view: NSView, type: T.Type) -> T? {
        if let match = view as? T {
            return match
        }
        for child in view.subviews {
            if let match = descendant(of: child, type: type) {
                return match
            }
        }
        return nil
    }
}

@MainActor
@Observable
private final class InteractionModel {
    var selection: UUID?
}

@MainActor
@Observable
private final class MutableInteractionModel {
    var rows: [ServiceEditorList.Row] = []
    var selection: UUID?
}

@MainActor
private struct MutableInteractionList: View {
    let model: MutableInteractionModel

    var body: some View {
        ServiceEditorList(
            columns: ["Argument"], rows: model.rows, selection: model.selection,
            emptyMessage: "No Arguments", addLabel: "Add", removeLabel: "Remove",
            select: { model.selection = $0 }, update: { _, _, _ in }, add: {}, remove: { _ in },
            move: { _, _ in }, drop: { _, _ in },
        )
        .frame(width: 680)
    }
}
