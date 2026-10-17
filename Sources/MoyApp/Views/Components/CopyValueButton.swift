import MoyKit
import SwiftUI

struct CopyValueButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let store: ServicesStore
    let identifier: ServiceIdentifier
    let item: String
    let value: String

    var body: some View {
        let isCopied = store.state.copyToast?.showsSuccess(for: identifier, item: item) == true
        Button {
            store.send(.copyFeedback(.copy(value, item: item, identifier: identifier)))
        } label: {
            CopyValueButtonLabel(isCopied: isCopied, reduceMotion: reduceMotion)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(isCopied ? "" : L10n.Services.copyItem(item))
        .accessibilityLabel(L10n.Services.copyItem(item))
        .accessibilityValue(isCopied ? L10n.Common.copied : "")
    }
}

struct CopyValueButtonLabel: View {
    let isCopied: Bool
    let reduceMotion: Bool

    var body: some View {
        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
            .imageScale(.small)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            .foregroundStyle(.secondary)
            .frame(width: 16, height: 16)
            .padding(2)
            .contentShape(Rectangle())
            .overlay(alignment: .bottomTrailing) {
                if isCopied {
                    CopySuccessTooltip()
                        .offset(y: -26)
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottomTrailing)))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isCopied)
    }
}

private struct CopySuccessTooltip: View {
    var body: some View {
        Text(L10n.Common.copied)
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
