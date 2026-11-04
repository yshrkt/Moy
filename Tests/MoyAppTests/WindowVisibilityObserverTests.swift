import AppKit
@testable import MoyApp
import Testing

@MainActor
@Suite("Detail window visibility", .serialized, .timeLimit(.minutes(1)))
struct WindowVisibilityObserverTests {
    @Test
    func `window notifications report visible minimized occluded and closed states`() async throws {
        var reports: [Bool] = []
        let view = WindowVisibilityObserver.VisibilityView { reports.append($0) }
        let window = VisibilityTestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer {
            view.stopObserving()
            window.close()
        }
        // WindowServerの表示状態に依存せず、AppKitが報告する値と通知の接続を検証します。
        window.reportsVisible = true
        post(NSWindow.didChangeOcclusionStateNotification, window: window)
        try await waitFor { reports.last == true }
        window.reportsOccluded = true
        post(NSWindow.didChangeOcclusionStateNotification, window: window)
        try await waitFor { reports.last == false }
        window.reportsOccluded = false
        post(NSWindow.didChangeOcclusionStateNotification, window: window)
        try await waitFor { reports.last == true }
        window.reportsMiniaturized = true
        post(NSWindow.didMiniaturizeNotification, window: window)
        try await waitFor { reports.last == false }
        window.reportsMiniaturized = false
        post(NSWindow.didDeminiaturizeNotification, window: window)
        try await waitFor { reports.last == true }
        window.reportsVisible = false
        post(NSWindow.didChangeOcclusionStateNotification, window: window)
        try await waitFor { reports.last == false }
        window.reportsVisible = true
        post(NSWindow.didChangeOcclusionStateNotification, window: window)
        try await waitFor { reports.last == true }
        post(NSWindow.willCloseNotification, window: window)
        try await waitFor { reports.last == false }
        view.stopObserving()
        post(NSWindow.didChangeOcclusionStateNotification, window: window)
        #expect(reports.last == false)
    }

    private func post(_ name: Notification.Name, window: NSWindow) {
        NotificationCenter.default.post(name: name, object: window)
    }

    private func waitFor(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(condition())
    }
}

@MainActor
private final class VisibilityTestWindow: NSWindow {
    var reportsVisible = false
    var reportsMiniaturized = false
    var reportsOccluded = false

    override var isVisible: Bool {
        reportsVisible
    }

    override var isMiniaturized: Bool {
        reportsMiniaturized
    }

    override var occlusionState: NSWindow.OcclusionState {
        reportsOccluded ? [] : .visible
    }
}
