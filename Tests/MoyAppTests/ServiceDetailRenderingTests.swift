import AppKit
@testable import MoyApp
import MoyKit
import NanoRedux
import SwiftUI
import Testing

@MainActor
@Suite("Service detail rendering", .serialized)
struct ServiceDetailRenderingTests {
    @Test(arguments: [false, true])
    func `renders long values at narrow and wide widths`(dark: Bool) throws {
        let service = try ServiceDefinition(
            identifier: ServiceIdentifier("layout-fixture"),
            displayName: "Layout Fixture",
            description: "Long paths and literal arguments",
            programArguments: ["/opt/homebrew/bin/tool", "--model",
                               "/Users/example/Models/a-very-long-model-directory/another-directory/model.safetensors",
                               "--message", "hello world", "", "$PORT"],
            workingDirectory: "/Users/example/Projects/a-very-long-directory-name/working-directory",
            environmentVariables: ["Z_PORT": "8080", "A_MODE": "development"],
            runAtLoad: true,
            keepAlive: false,
            throttleInterval: 60,
            standardOutPath: "/Users/example/Library/Logs/Moy/com.sputnik-apps.moy.layout-fixture.stdout.log",
            standardErrorPath: "/Users/example/Library/Logs/Moy/com.sputnik-apps.moy.layout-fixture.stderr.log",
        )
        let state = ServicesState()
        state.statuses[service.identifier] = ServiceStatus(
            identifier: service.identifier, registration: .enabled, runtime: .running(pid: 1952),
        )
        populateMetrics(in: state)
        state.copyToast = CopyToast(
            id: UUID(), identifier: service.identifier, item: "ProgramArguments", succeeded: true,
        )
        let store = StoreBuilder.reducer(
            initialState: state,
            reducer: ServicesReducer(dependencies: ServicesDependencies(
                serviceManagementUseCase: TestServiceManagementUseCase(), metricsClient: .idle,
            )),
        )
        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/detail-layout-qa", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for width in [550, 1000] {
            let renderer = ImageRenderer(content: ServiceDetailView(store: store, service: service).detailContent
                .frame(width: CGFloat(width))
                .background(dark ? Color(white: 0.14) : .white)
                .environment(\.colorScheme, dark ? .dark : .light))
            renderer.scale = 2
            let image = try #require(renderer.nsImage)
            let tiff = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let language = Bundle.main.preferredLocalizations.first ?? "unknown"
            try data.write(to: output.appendingPathComponent("\(language)-\(dark ? "dark" : "light")-\(width).png"))
            #expect(image.size.width == CGFloat(width))
        }

        try renderToast(identifier: service.identifier, dark: dark, output: output)
    }

    private func populateMetrics(in state: ServicesState) {
        state.metrics.physicalMemory = 32 * 1024 * 1024 * 1024
        let end = Date()
        for index in 0 ... 30 {
            let sample = makeSample(
                pid: 1952, cpu: .value(Double((index * 7) % 180)),
                memory: .value(UInt64(128 * 1024 * 1024 + index * 100_000)),
                timestamp: end.addingTimeInterval(Double(index - 30) * 2),
            )
            state.metrics.sample = sample
            state.metrics.history.append(sample)
        }
    }

    private func renderToast(identifier: ServiceIdentifier, dark: Bool, output: URL) throws {
        let toast = CopyToast(id: UUID(), identifier: identifier, item: "PID", succeeded: false)
        let toastRenderer = ImageRenderer(content: CopyToastView(toast: toast)
            .padding(20)
            .background(dark ? Color(white: 0.14) : .white)
            .environment(\.colorScheme, dark ? .dark : .light))
        toastRenderer.scale = 2
        let toastImage = try #require(toastRenderer.nsImage)
        let toastTIFF = try #require(toastImage.tiffRepresentation)
        let toastBitmap = try #require(NSBitmapImageRep(data: toastTIFF))
        let toastData = try #require(toastBitmap.representation(using: .png, properties: [:]))
        let language = Bundle.main.preferredLocalizations.first ?? "unknown"
        try toastData.write(to: output.appendingPathComponent("\(language)-toast-\(dark ? "dark" : "light").png"))
    }

    @Test(arguments: [false, true], [false, true])
    func `renders copy success with reduced motion and both appearances`(dark: Bool, reduceMotion: Bool) throws {
        let renderer = ImageRenderer(content: CopyValueButtonLabel(isCopied: true, reduceMotion: reduceMotion)
            .padding(.top, 60)
            .padding(.horizontal, 180)
            .padding(.bottom, 20)
            .background(dark ? Color(white: 0.14) : .white)
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let language = Bundle.main.preferredLocalizations.first ?? "unknown"
        let name = "\(language)-copy-\(dark ? "dark" : "light")-reduced-\(reduceMotion).png"
        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/detail-layout-qa", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try data.write(to: output.appendingPathComponent(name))
    }
}
