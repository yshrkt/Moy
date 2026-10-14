import Foundation
import MoyKit

enum CLIOutput {
    static func json(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func service(_ service: ServiceDefinition) {
        print("Identifier:         \(service.identifier.rawValue)")
        print("Kind:               \(service.kind.rawValue)")
        print("Launchd Label:      \(service.identifier.launchdLabel)")
        print("Name:               \(service.name)")
        print("Description:        \(service.description ?? "-")")
        print("ProgramArguments:   \(service.programArguments.map(shellQuoted).joined(separator: " "))")
        print("WorkingDirectory:   \(service.workingDirectory ?? "-")")
        print("RunAtLoad:          \(service.runAtLoad)")
        print("KeepAlive:          \(service.keepAlive)")
        print("ThrottleInterval:   \(service.throttleInterval.map(String.init) ?? "default")")
        print("StandardOutPath:    \(service.standardOutPath)")
        print("StandardErrorPath:  \(service.standardErrorPath)")
        if service.environmentVariables.isEmpty {
            print("Environment:        -")
        } else {
            print("Environment:")
            for (key, value) in service.environmentVariables.sorted(by: { $0.key < $1.key }) {
                print("  \(key)=\(value)")
            }
        }
    }

    static func status(_ status: ServiceStatus) {
        print([
            status.identifier.rawValue,
            status.registration.rawValue,
            runtime(status.runtime),
            lastExit(status.lastExitStatus),
        ].joined(separator: "\t"))
    }

    private static func runtime(_ runtime: ServiceStatus.Runtime) -> String {
        switch runtime {
        case .notLoaded: "not-loaded"
        case .waiting: "waiting"
        case let .running(pid): "running (pid \(pid))"
        }
    }

    private static func lastExit(_ status: Int32?) -> String {
        status.map { "last-exit \($0)" } ?? "no-exit-status"
    }

    private static func shellQuoted(_ value: String) -> String {
        guard !value.isEmpty else { return "''" }
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./"))
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
