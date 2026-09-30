@testable import MoyApp
import MoyKit
import Testing

@Suite("Service status presentation")
struct ServiceStatusPresentationTests {
    @Test
    func `shows loading until status is available`() {
        #expect(ServiceStatusPresentation(status: nil, hasError: false) == .loading)
    }

    @Test
    func `shows error when status lookup failed`() throws {
        let status = try makeStatus(registration: .enabled, runtime: .running(pid: 42))

        #expect(ServiceStatusPresentation(status: status, hasError: true) == .error)
    }

    @Test(arguments: [ServiceStatus.Registration.plistOnly, .loadedOnly])
    func `shows attention for inconsistent registration`(
        registration: ServiceStatus.Registration,
    ) throws {
        let status = try makeStatus(registration: registration, runtime: .notLoaded)

        #expect(ServiceStatusPresentation(status: status, hasError: false) == .needsAttention)
    }

    @Test
    func `shows one combined operational state`() throws {
        let running = try makeStatus(registration: .enabled, runtime: .running(pid: 42))
        let waiting = try makeStatus(registration: .enabled, runtime: .waiting)
        let disabled = try makeStatus(registration: .disabled, runtime: .notLoaded)

        #expect(ServiceStatusPresentation(status: running, hasError: false) == .running)
        #expect(ServiceStatusPresentation(status: waiting, hasError: false) == .waiting)
        #expect(ServiceStatusPresentation(status: disabled, hasError: false) == .disabled)
    }

    @Test
    func `treats an impossible enabled but unloaded combination as needing attention`() throws {
        let status = try makeStatus(registration: .enabled, runtime: .notLoaded)

        #expect(ServiceStatusPresentation(status: status, hasError: false) == .needsAttention)
    }

    private func makeStatus(
        registration: ServiceStatus.Registration,
        runtime: ServiceStatus.Runtime,
    ) throws -> ServiceStatus {
        try ServiceStatus(
            identifier: ServiceIdentifier("example"),
            registration: registration,
            runtime: runtime,
        )
    }
}
