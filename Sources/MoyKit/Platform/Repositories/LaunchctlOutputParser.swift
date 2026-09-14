import Foundation

struct LaunchctlOutputParser {
    struct State: Equatable {
        let pid: Int32?
        let lastExitStatus: Int32?
    }

    func parse(_ output: String) -> State {
        State(
            pid: integer(for: "pid", in: output),
            lastExitStatus: integer(for: "last exit code", in: output),
        )
    }

    static func isMissingService(_ output: String) -> Bool {
        output.localizedCaseInsensitiveContains("could not find service")
            || output.localizedCaseInsensitiveContains("service not found")
    }

    private func integer(for key: String, in output: String) -> Int32? {
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard fields.count == 2, fields[0] == key else { continue }
            return Int32(fields[1])
        }
        return nil
    }
}
