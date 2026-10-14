import ArgumentParser
import MoyKit

enum CLIParsing {
    static func identifier(_ value: String) throws -> ServiceIdentifier {
        do {
            return try ServiceIdentifier(value)
        } catch {
            throw ValidationError(error.localizedDescription)
        }
    }

    static func environment(_ values: [String]) throws -> [String: String] {
        try values.reduce(into: [:]) { result, value in
            guard let separator = value.firstIndex(of: "=") else {
                throw ValidationError("Environment variables must use KEY=VALUE: \(value)")
            }
            let key = String(value[..<separator])
            guard !key.isEmpty else {
                throw ValidationError("Environment variable names must not be empty.")
            }
            result[key] = String(value[value.index(after: separator)...])
        }
    }

    static func optionalText(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

extension ServiceKind: @retroactive ExpressibleByArgument {}
