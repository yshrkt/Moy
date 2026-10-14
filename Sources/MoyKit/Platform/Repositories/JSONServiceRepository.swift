import Darwin
import Foundation

public actor JSONServiceRepository: ServiceRepository {
    private struct Store: Codable {
        static let currentSchemaVersion = 1

        var schemaVersion: Int
        var services: [ServiceDefinition]

        static var empty: Self {
            Self(schemaVersion: currentSchemaVersion, services: [])
        }
    }

    private let paths: MoyPaths
    private let fileManager: FileManager
    private let labelChecker: any ServiceLabelChecking

    public init(
        paths: MoyPaths = .defaults(),
        fileManager: FileManager = .default,
        labelChecker: (any ServiceLabelChecking)? = nil,
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.labelChecker = labelChecker ?? LaunchctlServiceLabelChecker()
    }

    public func list() async throws -> [ServiceDefinition] {
        try withLock {
            try readStore().services.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    public func find(identifier: ServiceIdentifier) async throws -> ServiceDefinition {
        try withLock {
            guard let service = try readStore().services.first(where: { $0.identifier == identifier }) else {
                throw MoyError.serviceNotFound(identifier.rawValue)
            }
            return service
        }
    }

    public func create(_ newService: ServiceDraft) async throws -> ServiceDefinition {
        try validateExecutable(newService.programArguments)
        if try await labelChecker.isLoaded(label: newService.identifier.launchdLabel) {
            throw MoyError.duplicateService(newService.identifier.rawValue)
        }
        return try withLock {
            var store = try readStore()
            try validateAvailability(of: newService.identifier, in: store)
            let standardOutPath = newService.standardOutPath.nilIfEmpty
                ?? paths.standardOutFile(identifier: newService.identifier, kind: newService.kind).path
            let defaultStandardErrorPath = paths.standardErrorFile(
                identifier: newService.identifier, kind: newService.kind,
            ).path
            let standardErrorPath = newService.standardErrorPath.nilIfEmpty ?? defaultStandardErrorPath
            let service = ServiceDefinition(
                identifier: newService.identifier,
                kind: newService.kind,
                displayName: newService.displayName.nilIfEmpty,
                description: newService.description.nilIfEmpty,
                programArguments: newService.programArguments,
                workingDirectory: newService.workingDirectory.nilIfEmpty,
                environmentVariables: newService.environmentVariables,
                runAtLoad: newService.runAtLoad,
                keepAlive: newService.keepAlive,
                throttleInterval: newService.throttleInterval,
                standardOutPath: standardOutPath,
                standardErrorPath: standardErrorPath,
            )
            try ServiceValidator.validate(service)
            store.services.append(service)
            try writeStore(store)
            return service
        }
    }

    public func update(_ service: ServiceDefinition) async throws {
        try update(service, expected: nil)
    }

    public func update(_ service: ServiceDefinition, expected: ServiceDefinition) async throws {
        try update(service, expected: Optional(expected))
    }

    private func update(_ service: ServiceDefinition, expected: ServiceDefinition?) throws {
        try validateExecutable(service.programArguments)
        try ServiceValidator.validate(service)
        try withLock {
            var store = try readStore()
            guard let index = store.services.firstIndex(where: { $0.identifier == service.identifier }) else {
                throw MoyError.serviceNotFound(service.identifier.rawValue)
            }
            if let expected, store.services[index] != expected {
                throw MoyError.serviceChanged
            }
            guard store.services[index].kind == service.kind else { throw MoyError.kindCannotChange }
            store.services[index] = service
            try writeStore(store)
        }
    }

    public func remove(identifier: ServiceIdentifier) async throws {
        try withLock {
            var store = try readStore()
            guard let index = store.services.firstIndex(where: { $0.identifier == identifier }) else {
                throw MoyError.serviceNotFound(identifier.rawValue)
            }
            store.services.remove(at: index)
            try writeStore(store)
        }
    }
}

private extension JSONServiceRepository {
    func validateExecutable(_ arguments: [String]) throws {
        let path = arguments.first ?? ""
        var isDirectory: ObjCBool = false
        guard path.hasPrefix("/"), fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw MoyError.executableNotFound(path)
        }
        guard !isDirectory.boolValue, fileManager.isExecutableFile(atPath: path) else {
            throw MoyError.executableNotRunnable(path)
        }
    }

    func prepareDataDirectory() throws {
        do {
            try fileManager.createDirectory(at: paths.dataDirectory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.dataDirectory.path)
        } catch {
            throw MoyError.fileOperation(path: paths.dataDirectory.path, reason: error.localizedDescription)
        }
    }

    func withLock<T>(_ operation: () throws -> T) throws -> T {
        try prepareDataDirectory()
        let descriptor = Darwin.open(paths.lockFile.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw MoyError.lockUnavailable(path: paths.lockFile.path)
        }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw MoyError.lockUnavailable(path: paths.lockFile.path)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private func readStore() throws -> Store {
        guard fileManager.fileExists(atPath: paths.servicesFile.path) else { return .empty }
        do {
            let data = try Data(contentsOf: paths.servicesFile)
            let store = try JSONDecoder().decode(Store.self, from: data)
            guard store.schemaVersion == Store.currentSchemaVersion else {
                throw MoyError.unsupportedSchema(
                    found: store.schemaVersion,
                    supported: Store.currentSchemaVersion,
                )
            }
            guard Set(store.services.map(\.identifier)).count == store.services.count else {
                throw MoyError.corruptStorage(path: paths.servicesFile.path, reason: "Duplicate service identifiers")
            }
            do {
                try store.services.forEach(ServiceValidator.validate)
            } catch {
                throw MoyError.corruptStorage(path: paths.servicesFile.path, reason: error.localizedDescription)
            }
            return store
        } catch let error as MoyError {
            throw error
        } catch {
            throw MoyError.corruptStorage(path: paths.servicesFile.path, reason: error.localizedDescription)
        }
    }

    private func writeStore(_ store: Store) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(store)
            try data.write(to: paths.servicesFile, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.servicesFile.path)
        } catch {
            throw MoyError.fileOperation(path: paths.servicesFile.path, reason: error.localizedDescription)
        }
    }

    private func validateAvailability(of identifier: ServiceIdentifier, in store: Store) throws {
        let isStored = store.services.contains { $0.identifier == identifier }
        let hasPlist = ServiceKind.allCases.contains {
            fileManager.fileExists(atPath: paths.plistFile(identifier: identifier, kind: $0).path)
        }
        if isStored || hasPlist {
            throw MoyError.duplicateService(identifier.rawValue)
        }
    }
}

private extension String? {
    var nilIfEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
