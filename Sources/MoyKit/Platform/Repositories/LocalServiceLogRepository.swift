import Darwin
import Foundation

/// Prepares output files as the invoking user, preserving existing data and permissions.
public struct LocalServiceLogRepository: ServiceLogRepository {
    public init() {}

    public func prepare(for service: ServiceDefinition) async throws {
        guard geteuid() != 0 else { throw MoyError.invalidInvokingUser }
        try ServiceValidator.validate(service)
        for path in Set([service.standardOutPath, service.standardErrorPath]).sorted() {
            try prepareFile(at: path)
        }
    }

    private func prepareFile(at path: String) throws {
        let directory = URL(filePath: path).deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw MoyError.fileOperation(path: directory.path, reason: error.localizedDescription)
        }
        // Exclusive creation avoids truncating an existing file, including concurrent enable attempts.
        let created = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        if created >= 0 {
            defer { Darwin.close(created) }
            guard fchmod(created, S_IRUSR | S_IWUSR) == 0 else { throw fileError(path) }
            return
        }
        guard errno == EEXIST else { throw fileError(path) }
        // No truncate/chown/chmod. Nonblocking open prevents hanging on a FIFO or other special file.
        let existing = Darwin.open(path, O_WRONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard existing >= 0 else { throw fileError(path) }
        defer { Darwin.close(existing) }
        var attributes = stat()
        guard fstat(existing, &attributes) == 0 else { throw fileError(path) }
        guard attributes.st_mode & S_IFMT == S_IFREG else {
            throw MoyError.fileOperation(path: path, reason: String(cString: strerror(EINVAL)))
        }
    }

    private func fileError(_ path: String) -> MoyError {
        .fileOperation(path: path, reason: String(cString: strerror(errno)))
    }
}
