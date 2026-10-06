import SwiftUI

struct RefreshButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationTrigger = false

    let action: () -> Void

    var body: some View {
        Button {
            animationTrigger.toggle()
            action()
        } label: {
            Image(systemName: "arrow.clockwise")
                .symbolEffect(.rotate.clockwise, options: .nonRepeating, value: animationTrigger)
                .symbolEffectsRemoved(reduceMotion)
        }
        .help(L10n.Common.refresh)
        .accessibilityLabel(L10n.Common.refresh)
    }
}
