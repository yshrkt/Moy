import Darwin
import Foundation

/// Identifies the owner of the definitions independently of the effective root user.
public struct MoyUserContext: Equatable, Sendable {
    public let userID: uid_t
    public let homeDirectory: URL

    public static func resolve(
        effectiveUserID: uid_t = geteuid(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        requestedUserID: uid_t? = nil,
    ) throws -> Self {
        let userID: uid_t
        if effectiveUserID == 0 {
            guard let original = requestedUserID ?? environment["SUDO_UID"].flatMap(uid_t.init), original != 0 else {
                throw MoyError.invalidInvokingUser
            }
            userID = original
        } else {
            guard requestedUserID == nil || requestedUserID == effectiveUserID else {
                throw MoyError.invalidInvokingUser
            }
            userID = effectiveUserID
        }
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16384)
        let home: String = try buffer.withUnsafeMutableBufferPointer { storage in
            guard getpwuid_r(userID, &entry, storage.baseAddress, storage.count, &result) == 0,
                  result != nil, let directory = entry.pw_dir else { throw MoyError.invalidInvokingUser }
            return String(cString: directory)
        }
        return Self(userID: userID, homeDirectory: URL(filePath: home))
    }

    public var paths: MoyPaths {
        .defaults(environment: geteuid() == 0 ? [:] : ProcessInfo.processInfo.environment, homeDirectory: homeDirectory)
    }
}
