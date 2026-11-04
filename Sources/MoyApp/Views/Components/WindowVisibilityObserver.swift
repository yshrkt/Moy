import AppKit
import SwiftUI

/// Windowのクローズ・最小化・非表示を含めて、実際に画面が表示されているかを通知します。
struct WindowVisibilityObserver: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context _: Context) -> VisibilityView {
        VisibilityView(onChange: onChange)
    }

    func updateNSView(_ nsView: VisibilityView, context _: Context) {
        nsView.onChange = onChange
    }

    static func dismantleNSView(_ nsView: VisibilityView, coordinator _: ()) {
        nsView.stopObserving()
    }

    @MainActor
    final class VisibilityView: NSView {
        var onChange: @MainActor (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        private var lastVisibility: Bool?

        init(onChange: @escaping @MainActor (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { return }
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                         NSWindow.didDeminiaturizeNotification]
            {
                let observer = NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main,
                ) { [weak self] _ in
                    Task { @MainActor in self?.updateVisibility() }
                }
                observers.append(observer)
            }
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main,
            ) { [weak self] _ in
                Task { @MainActor in self?.report(false) }
            })
            updateVisibility()
        }

        func stopObserving() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers.removeAll()
            report(false)
        }

        private func updateVisibility() {
            report(window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false)
        }

        private func report(_ visible: Bool) {
            guard lastVisibility != visible else { return }
            lastVisibility = visible
            onChange(visible)
        }
    }
}
