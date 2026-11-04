import MoyKit
import Testing

struct ServiceStatusMetricsTests {
    @Test
    func `only a registered running process has a metrics PID`() throws {
        let identifier = try ServiceIdentifier("worker")
        for registration in [ServiceStatus.Registration.disabled, .enabled, .plistOnly, .loadedOnly] {
            let status = ServiceStatus(identifier: identifier, registration: registration, runtime: .running(pid: 123))
            #expect(status.metricsPID == (registration == .enabled ? 123 : nil))
        }
        for runtime in [ServiceStatus.Runtime.notLoaded, .waiting, .running(pid: 0), .running(pid: -1)] {
            #expect(ServiceStatus(identifier: identifier, registration: .enabled, runtime: runtime).metricsPID == nil)
        }
    }
}
