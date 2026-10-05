import MoyKit
import SwiftUI

struct CopyValueButton: View {
    let store: ServicesStore
    let identifier: ServiceIdentifier
    let item: String
    let value: String

    var body: some View {
        Button {
            store.send(.copyValue(value, item: item, identifier: identifier))
        } label: {
            Image(systemName: "doc.on.doc")
                .imageScale(.small)
                .padding(2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(L10n.Services.copyItem(item))
        .accessibilityLabel(L10n.Services.copyItem(item))
    }
}
