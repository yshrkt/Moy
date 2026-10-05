import AppKit
@testable import MoyApp
import Testing

@Suite("Command line presentation")
struct CommandLineFormatterTests {
    @Test
    func `formats a command with one argument on each line`() {
        #expect(CommandLineFormatter.format([]).isEmpty)
        #expect(CommandLineFormatter.format(["/usr/bin/true"]) == "/usr/bin/true")
        #expect(CommandLineFormatter.format(["/usr/bin/tool", "--arg1", "value1"])
            == "/usr/bin/tool \\\n--arg1 \\\nvalue1")
        #expect(CommandLineFormatter.format([""]) == "''")
        #expect(CommandLineFormatter.format(["$PORT"]) == "'$PORT'")
        #expect(CommandLineFormatter.format(["it's"]) == "'it'\\''s'")
    }

    @Test(arguments: [
        ["/usr/bin/true"],
        ["/path with spaces/tool", "--arg1", "value1"],
        ["/usr/bin/tool", "", "  spaces  ", "\"quoted\"", "it's", "$PORT", "${PORT}"],
        ["/usr/bin/tool", "a\nb", "line\rbreak", "tab\tvalue", "日本語", "é", "\\", "~", "*", "[abc]"],
        ["/usr/bin/tool", "$(printf injected)", "`printf injected`", "; echo injected", "# comment", "a|b", "a>b"],
    ])
    func `zsh restores the exact argument array without executing the command`(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // set -- only parses the formatted words; the service executable is never invoked.
        process.arguments = ["-f", "-c", "set -- \(CommandLineFormatter.format(arguments))\nprintf '%s\\0' \"$@\""]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let text = try #require(String(data: data, encoding: .utf8))
        let restored = text.components(separatedBy: "\0").dropLast()
        #expect(Array(restored) == arguments)
    }

    @MainActor
    @Test
    func `copies the same formatted command as plain text`() {
        let command = CommandLineFormatter.format(["/usr/bin/tool", "", "$PORT", "a\nb", "it's"])
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("previous contents", forType: .string)
        CommandClipboard.copy(command, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == command)
    }
}
