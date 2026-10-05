import Foundation

enum CommandLineFormatter {
    static func format(_ arguments: [String]) -> String {
        arguments.map(quote).joined(separator: " \\\n")
    }

    private static func quote(_ argument: String) -> String {
        guard !argument.isEmpty else { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./")
        if argument.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return argument
        }
        return "'\(argument.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
