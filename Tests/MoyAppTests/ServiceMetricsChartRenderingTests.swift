import AppKit
@testable import MoyApp
import MoyMetrics
import SwiftUI
import Testing

@MainActor
@Suite("Metrics chart rendering", .serialized)
struct ServiceMetricsChartRenderingTests {
    @Test(arguments: ["waiting", "gaps", "zero"], [false, true])
    func `renders sparse unavailable and zero charts`(scenario: String, dark: Bool) throws {
        let state = ServicesState()
        state.metrics.physicalMemory = 32 * 1024 * 1024 * 1024
        let end = Date()
        for index in 0 ... (scenario == "waiting" ? 0 : 30) {
            let unavailable = scenario == "gaps" && (10 ... 15).contains(index)
            let cpu: MetricValue<Double> = if scenario == "waiting" {
                .waiting
            } else if unavailable {
                .failed(.counterOverflow)
            } else {
                .value(scenario == "zero" ? 0 : Double(index * 5))
            }
            let sample = makeSample(
                pid: 10, cpu: cpu, memory: .value(scenario == "zero" ? 0 : 128 * 1024 * 1024),
                timestamp: end.addingTimeInterval(Double(index - 30) * 2),
            )
            state.metrics.sample = sample
            state.metrics.history.append(sample)
        }
        let renderer = ImageRenderer(content: ServiceResourceUsageView(state: state, pid: 10)
            .padding(16)
            .frame(width: 470)
            .background(dark ? Color(white: 0.14) : .white)
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/detail-layout-qa", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let language = Bundle.main.preferredLocalizations.first ?? "unknown"
        let filename = "\(language)-metrics-\(scenario)-\(dark ? "dark" : "light").png"
        try data.write(to: output.appendingPathComponent(filename))
        #expect(image.size.width == 470)
    }
}
