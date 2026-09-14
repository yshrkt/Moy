import AppKit
import MoyKit
import SwiftUI

@main
struct MoyApp: App {
    var body: some Scene {
        MenuBarExtra("Moy", systemImage: "terminal") {
            Text(L10n.App.placeholder)
            Divider()
            Button(L10n.Common.quit) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
