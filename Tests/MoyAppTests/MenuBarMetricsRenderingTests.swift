import AppKit
@testable import MoyApp
import MoyKit
import MoyMetrics
import NanoRedux
import SwiftUI
import Testing

@MainActor
@Suite("Menu metrics rendering", .serialized)
struct MenuBarMetricsRenderingTests {
    @Test(arguments: [false, true], [6, 12])
    func `renders secondary metrics and keeps long menus scrollable`(dark: Bool, count: Int) async throws {
        let state = try makeState(count: count)
        let store = StoreBuilder.reducer(initialState: state, reducer: ServicesReducer(dependencies: .init(
            serviceManagementUseCase: TestServiceManagementUseCase(), metricsClient: .idle,
        )))
        // ScrollViewを含むメニューはImageRendererではなく、実際のAppKitビューで描画します。
        let host = NSHostingView(rootView: MenuBarServicesView(store: store)
            .background(dark ? Color(white: 0.14) : .white)
            .environment(\.colorScheme, dark ? .dark : .light))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [], backing: .buffered, defer: false,
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/menu-layout-qa", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let language = Bundle.main.preferredLocalizations.first ?? "unknown"
        let filename = "\(language)-\(count)-\(dark ? "dark" : "light").png"
        try data.write(to: output.appendingPathComponent(filename))
        #expect(host.bounds.width == 280)
        #expect(host.bounds.height > 0 && host.bounds.height < 700)
    }

    private func makeState(count: Int) throws -> ServicesState {
        let state = ServicesState()
        for index in 0 ..< count {
            let identifier = try ServiceIdentifier("worker-\(index)")
            let service = ServiceDefinition(
                identifier: identifier, kind: index.isMultiple(of: 2) ? .launchAgent : .launchDaemon,
                displayName: index == 0 ? "API Server with a very long service name" : "Worker \(index)",
                programArguments: ["/usr/bin/true"],
                standardOutPath: "/tmp/test.out", standardErrorPath: "/tmp/test.err",
            )
            state.services.append(service)
            let pid = Int32(100 + index)
            state.statuses[identifier] = .init(
                identifier: identifier, registration: index == 5 ? .disabled : .enabled,
                runtime: index == 4 ? .waiting : .running(pid: pid),
            )
            var process = ServicesProcessMetricsState(id: UUID(), pid: pid)
            if index == 2 {
                process.isUnavailable = true
            } else if index == 6 {
                process.sample = makeSample(pid: pid, cpu: .waiting)
            } else if index == 8 {
                process.sample = makeSample(pid: pid, memory: .failed(.counterOverflow))
            } else if index != 3 {
                process.sample = makeSample(pid: pid, cpu: .value(index == 1 ? 250.1 : 12.3))
            }
            state.metrics.processes[pid] = process
        }
        return state
    }
}
