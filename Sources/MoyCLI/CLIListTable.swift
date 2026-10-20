import Foundation
import MoyKit

enum CLIListTable {
    static func render(_ services: [ServiceDefinition]) -> String {
        let rows = [["IDENTIFIER", "KIND", "NAME", "PROGRAM"]] + services.map { service in
            let kind = switch service.kind {
            case .launchAgent: "LaunchAgent"
            case .launchDaemon: "LaunchDaemon"
            }
            return [
                service.identifier.rawValue,
                kind,
                abbreviated(singleLine(service.name), maximumWidth: 30),
                singleLine(service.programArguments[0]),
            ]
        }
        let widths = (0 ..< 3).map { column in rows.map { width($0[column]) }.max() ?? 0 }
        return rows.map { row in
            let columns = (0 ..< 3).map { column in
                row[column] + String(repeating: " ", count: widths[column] - width(row[column]) + 2)
            }
            return columns.joined() + row[3]
        }.joined(separator: "\n")
    }

    private static func singleLine(_ value: String) -> String {
        String(value.unicodeScalars.map { scalar -> Character in
            scalar.properties.generalCategory == .control || CharacterSet.newlines.contains(scalar)
                ? " " : Character(String(scalar))
        })
    }

    private static func abbreviated(_ value: String, maximumWidth: Int) -> String {
        guard width(value) > maximumWidth else { return value }
        var result = ""
        var usedWidth = 0
        for character in value {
            let characterWidth = width(character)
            guard usedWidth + characterWidth <= maximumWidth - 1 else { break }
            result.append(character)
            usedWidth += characterWidth
        }
        return result + "…"
    }

    private static func width(_ value: String) -> Int {
        value.reduce(0) { $0 + width($1) }
    }

    private static func width(_ character: Character) -> Int {
        let scalars = character.unicodeScalars
        // Treat emoji sequences as one wide glyph, preserving grapheme clusters when truncating.
        if scalars.contains(where: \.properties.isEmojiPresentation) ||
            (scalars.contains("\u{FE0F}") && scalars.contains(where: \.properties.isEmoji))
        {
            return 2
        }
        return scalars.map { scalar in
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark, .format: return 0
            default: break
            }
            // Wide and fullwidth CJK characters; ambiguous characters use one terminal column.
            switch scalar.value {
            case 0x1100 ... 0x115F, 0x2329 ... 0x232A, 0x2E80 ... 0x303E, 0x3040 ... 0xA4CF,
                 0xAC00 ... 0xD7A3, 0xF900 ... 0xFAFF, 0xFE10 ... 0xFE19, 0xFE30 ... 0xFE6F,
                 0xFF01 ... 0xFF60, 0xFFE0 ... 0xFFE6, 0x1B000 ... 0x1B2FF, 0x20000 ... 0x3FFFD:
                return 2
            default: return 1
            }
        }.max() ?? 0
    }
}
