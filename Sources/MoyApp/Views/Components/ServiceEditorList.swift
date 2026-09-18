import SwiftUI
import UniformTypeIdentifiers

/// Shared table chrome and keyboard behavior for the service's editable lists.
struct ServiceEditorList: View {
    struct Row: Identifiable {
        let id: UUID
        let values: [String]
    }

    private struct Cell: Hashable {
        let rowID: UUID
        let column: Int
    }

    let columns: [String]
    let rows: [Row]
    let selection: UUID?
    let emptyMessage: String
    let addLabel: String
    let removeLabel: String
    let select: (UUID?) -> Void
    let update: (UUID, Int, String) -> Void
    let add: () -> Void
    let remove: (UUID) -> Void
    var move: ((UUID, Int) -> Void)?
    var drop: ((UUID, Int) -> Void)?

    @FocusState private var focusedCell: Cell?
    @FocusState private var addFocused: Bool
    @FocusState private var tableFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    private let rowContentHeight: CGFloat = 28
    private let rowSpacing: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            table
                .frame(height: 32 + (rowContentHeight + rowSpacing) * CGFloat(max(2, rows.count)))
                .overlay {
                    if rows.isEmpty {
                        Text(emptyMessage)
                            .foregroundStyle(.secondary)
                            .padding(.top, 28)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: rows.map(\.id)) { oldIDs, newIDs in
                    if let added = newIDs.first(where: { !oldIDs.contains($0) }) {
                        focusedCell = Cell(rowID: added, column: 0)
                    } else if let focusedCell, !newIDs.contains(focusedCell.rowID) {
                        endEditing()
                    }
                }
                .onChange(of: selection) { _, id in
                    if let focusedCell, focusedCell.rowID != id {
                        endEditing()
                    }
                }
            Divider()
            controls
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(.separator, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .onChange(of: focusedCell) { _, cell in
            if let cell {
                select(cell.rowID)
            }
        }
    }

    private var table: some View {
        Table(of: Row.self, selection: Binding(get: { selection }, set: { select($0) })) {
            TableColumn(columns[0]) { row in
                cell(row, column: 0)
            }
            if columns.count > 1 {
                TableColumn(columns[1]) { row in
                    cell(row, column: 1)
                }
            }
        } rows: {
            if drop != nil, isEnabled {
                ForEach(rows) { row in
                    TableRow(row)
                        .draggable(ServiceArgumentDrag(id: row.id))
                }
                .dropDestination(for: ServiceArgumentDrag.self) { index, items in
                    guard isEnabled, items.count == 1, let item = items.first else { return }
                    drop?(item.id, index)
                }
            } else {
                ForEach(rows) { row in
                    TableRow(row)
                }
            }
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.enabled)
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        .focused($tableFocused)
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            guard isEnabled, focusedCell == nil, let selection else { return .ignored }
            remove(selection)
            return .handled
        }
        .onKeyPress(.return) {
            guard focusedCell == nil, let selection else { return .ignored }
            focusedCell = Cell(rowID: selection, column: 0)
            return .handled
        }
        .onKeyPress(.escape) {
            guard focusedCell != nil else { return .ignored }
            endEditing()
            return .handled
        }
    }

    @ViewBuilder
    private func cell(_ row: Row, column: Int) -> some View {
        let cell = Cell(rowID: row.id, column: column)
        // Keep the field mounted so focus requests always target an existing control.
        // The table receives the first click; once selected, the field receives the
        // next click and enters text editing.
        TextField(columns[column], text: Binding(
            get: { row.values[column] },
            set: { update(row.id, column, $0) },
        ))
        .labelsHidden()
        .textFieldStyle(.plain)
        .focused($focusedCell, equals: cell)
        .onSubmit { endEditing() }
        .onKeyPress(keys: [.tab]) { key in
            editAdjacentCell(to: cell, backwards: key.modifiers.contains(.shift))
            return .handled
        }
        .allowsHitTesting(selection == row.id)
        .font(.system(.body, design: .monospaced))
        .accessibilityLabel(columns[column])
        .frame(maxWidth: .infinity, minHeight: rowContentHeight, alignment: .leading)
    }

    private func endEditing() {
        focusedCell = nil
        tableFocused = true
    }

    private func editAdjacentCell(to cell: Cell, backwards: Bool) {
        guard let row = rows.firstIndex(where: { $0.id == cell.rowID }) else { return }
        let next = row * columns.count + cell.column + (backwards ? -1 : 1)
        guard (0 ..< rows.count * columns.count).contains(next) else {
            endEditing()
            if !backwards {
                addFocused = true
            }
            return
        }
        focusedCell = Cell(rowID: rows[next / columns.count].id, column: next % columns.count)
    }

    private var controls: some View {
        HStack(spacing: 4) {
            control(addLabel, symbol: "plus", action: add)
                .focused($addFocused)
            control(removeLabel, symbol: "minus") {
                if let selection {
                    remove(selection)
                }
            }
            .disabled(selection == nil)
            if move != nil {
                Divider().frame(height: 16).padding(.horizontal, 4)
                control(L10n.Services.moveArgumentUp, symbol: "chevron.up") { moveSelection(by: -1) }
                    .disabled(!canMoveSelection(by: -1))
                control(L10n.Services.moveArgumentDown, symbol: "chevron.down") { moveSelection(by: 1) }
                    .disabled(!canMoveSelection(by: 1))
            }
            Spacer()
        }
        .padding(4)
        .background(.quaternary.opacity(0.2))
    }

    private func control(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }

    private func canMoveSelection(by offset: Int) -> Bool {
        guard let index = rows.firstIndex(where: { $0.id == selection }) else { return false }
        return rows.indices.contains(index + offset)
    }

    private func moveSelection(by offset: Int) {
        guard let selection, let index = rows.firstIndex(where: { $0.id == selection }),
              rows.indices.contains(index + offset)
        else { return }
        move?(selection, index + offset)
    }
}

private struct ServiceArgumentDrag: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .moyServiceArgument)
    }
}

private extension UTType {
    static let moyServiceArgument = UTType(exportedAs: "com.sputnik-apps.moy.editor-argument", conformingTo: .data)
}
