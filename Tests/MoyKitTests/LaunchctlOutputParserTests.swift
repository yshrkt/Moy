@testable import MoyKit
import Testing

struct LaunchctlOutputParserTests {
    @Test
    func `parses running process and last exit status`() {
        let output = """
        gui/501/com.sputnik-apps.moy.a1b2c3d4 = {
            state = running
            pid = 4212
            last exit code = 7
        }
        """

        let state = LaunchctlOutputParser().parse(output)

        #expect(state.pid == 4212)
        #expect(state.lastExitStatus == 7)
    }

    @Test
    func `waiting service has no PID`() {
        let state = LaunchctlOutputParser().parse("state = not running\nlast exit code = 0")

        #expect(state.pid == nil)
        #expect(state.lastExitStatus == 0)
    }
}
