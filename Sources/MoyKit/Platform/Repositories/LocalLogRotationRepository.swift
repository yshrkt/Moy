import Darwin
import Foundation

/// Synchronous filesystem operations under one cross-process lock. No await while locked.
public struct LocalLogRotationRepository: Sendable {
    public let paths: MoyPaths

    public init(paths: MoyPaths = .defaults()) {
        self.paths = paths
    }

    public func settings() throws -> LogRotationSettings {
        try withLock { try readSettings() }
    }

    public func save(_ settings: LogRotationSettings) throws {
        try settings.validate()
        try withLock {
            _ = try readSettings()
            try write(settings, to: settingsURL)
        }
    }

    public func failures() throws -> [String] {
        try withLock {
            guard FileManager.default.fileExists(atPath: reportURL.path) else { return [] }
            return try decode([String].self, from: reportURL)
        }
    }

    public func rotate() throws {
        try withLock {
            do { try performRotation() } catch {
                if case LogRotationError.files = error {
                    throw error
                }
                try write([error.localizedDescription], to: reportURL)
                throw error
            }
        }
    }

    private func performRotation() throws {
        let settings = try readSettings()
        guard settings.isEnabled else { return }
        var failures: [String] = []
        if FileManager.default.fileExists(atPath: paths.logDirectory.path) {
            let directory = open(paths.logDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directory >= 0 else { throw fileError(paths.logDirectory.path) }
            defer { close(directory) }
            let entries = try FileManager.default.contentsOfDirectory(atPath: paths.logDirectory.path)
            for name in entries.sorted() where name.hasSuffix(".log") {
                do { try rotate(name, directory: directory, settings: settings) } catch {
                    failures.append(error.localizedDescription)
                }
            }
        }
        try write(failures, to: reportURL)
        if !failures.isEmpty {
            throw LogRotationError.files(failures)
        }
    }

    private var settingsURL: URL {
        paths.dataDirectory.appending(path: "log-rotation.json")
    }

    private var reportURL: URL {
        paths.dataDirectory.appending(path: "log-rotation-report.json")
    }

    private func readSettings() throws -> LogRotationSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return .init() }
        let settings = try decode(LogRotationSettings.self, from: settingsURL)
        try settings.validate()
        return settings
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        do { return try JSONDecoder().decode(type, from: Data(contentsOf: url)) } catch {
            throw MoyError.corruptStorage(path: url.path, reason: error.localizedDescription)
        }
    }

    private func write(_ value: some Encodable, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        guard geteuid() != 0 else { throw MoyError.invalidInvokingUser }
        try FileManager.default.createDirectory(
            at: paths.dataDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700],
        )
        let path = paths.dataDirectory.appending(path: "log-rotation.lock").path
        let descriptor = open(path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw fileError(path) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw MoyError.lockUnavailable(path: path) }
        defer { flock(descriptor, LOCK_UN) }
        do { return try operation() } catch let error as MoyError {
            throw error
        } catch let error as LogRotationError {
            throw error
        } catch {
            throw MoyError.fileOperation(path: paths.dataDirectory.path, reason: error.localizedDescription)
        }
    }

    private func rotate(_ name: String, directory: Int32, settings: LogRotationSettings) throws {
        var attributes = stat()
        guard fstatat(directory, name, &attributes, AT_SYMLINK_NOFOLLOW) == 0 else { throw fileError(name) }
        guard attributes.st_mode & S_IFMT == S_IFREG else { return }
        let source = openat(directory, name, O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard source >= 0 else { throw fileError(name) }
        defer { close(source) }
        guard fstat(source, &attributes) == 0 else { throw fileError(name) }
        // Do not alter root-owned or multiply-linked files through a user-writable directory.
        guard attributes.st_mode & S_IFMT == S_IFREG,
              attributes.st_uid == geteuid(), attributes.st_nlink == 1
        else {
            throw MoyError.fileOperation(path: name, reason: "Log must be a user-owned regular file with one link.")
        }
        guard attributes.st_size >= Int64(settings.maximumSizeMB) * 1_000_000 else { return }
        let temporary = ".\(name).\(UUID().uuidString).tmp"
        let destination = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard destination >= 0 else { throw fileError(name) }
        defer { close(destination); unlinkat(directory, temporary, 0) }
        // Copy only the initial size so continuous writers cannot prevent completion.
        try copy(source: source, destination: destination, size: attributes.st_size, name: name)
        guard fsync(destination) == 0 else { throw fileError(name) }
        try archive(name, temporary: temporary, directory: directory, generations: settings.generations)
        guard ftruncate(source, 0) == 0 else { throw fileError(name) }
    }

    private func copy(source: Int32, destination: Int32, size: Int64, name: String) throws {
        var remaining = size
        var buffer = [UInt8](repeating: 0, count: 65536)
        while remaining > 0 {
            let count = read(source, &buffer, min(buffer.count, Int(remaining)))
            if count < 0, errno == EINTR {
                continue
            }
            guard count >= 0 else { throw fileError(name) }
            guard count > 0 else {
                throw MoyError.fileOperation(
                    path: name, reason: "Log changed during copying; original was not truncated.",
                )
            }
            try buffer.withUnsafeBytes { bytes in
                var offset = 0
                while offset < count {
                    let written = Darwin.write(destination, bytes.baseAddress!.advanced(by: offset), count - offset)
                    if written < 0, errno == EINTR {
                        continue
                    }
                    guard written > 0 else { throw fileError(name) }
                    offset += written
                }
            }
            remaining -= Int64(count)
        }
    }

    private func archive(_ name: String, temporary: String, directory: Int32, generations: Int) throws {
        // Validate every archive before moving any of them; never follow archive links.
        for generation in 1 ... 100 {
            let archive = "\(name).\(generation)"
            var attributes = stat()
            if fstatat(directory, archive, &attributes, AT_SYMLINK_NOFOLLOW) == 0 {
                guard attributes.st_mode & S_IFMT == S_IFREG, attributes.st_uid == geteuid(),
                      attributes.st_nlink == 1
                else {
                    throw MoyError.fileOperation(path: archive, reason: "Invalid archive file.")
                }
            } else if errno != ENOENT {
                throw fileError(archive)
            }
        }
        for generation in stride(from: 100, through: 1, by: -1) {
            let archive = "\(name).\(generation)"
            if generation >= generations {
                if unlinkat(directory, archive, 0) != 0, errno != ENOENT {
                    throw fileError(archive)
                }
            } else if renameat(directory, archive, directory, "\(name).\(generation + 1)") != 0,
                      errno != ENOENT
            {
                throw fileError(archive)
            }
        }
        guard renameat(directory, temporary, directory, "\(name).1") == 0 else { throw fileError(name) }
    }

    private func fileError(_ path: String) -> MoyError {
        .fileOperation(path: path, reason: String(cString: strerror(errno)))
    }
}
