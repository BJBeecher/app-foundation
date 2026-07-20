@preconcurrency import Combine
import CryptoKit
import Foundation

public protocol CodableCacheService: Sendable {
    func save<Value: Codable & Sendable>(_ value: Value, key: String, expiry: Date?) async throws
    func save<Value: Codable & Sendable>(_ value: Value, key: String) async throws
    func get<Value: Codable & Sendable>(key: String, as type: Value.Type) async throws -> Value?
    func update<Value: Codable & Sendable>(
        key: String,
        as type: Value.Type,
        update: @Sendable (inout Value) -> Void
    ) async throws
    func contains(key: String) async throws -> Bool
    func observe<Value: Codable & Sendable>(key: String, as type: Value.Type) -> AsyncStream<Value>
    func delete(key: String) async throws
    func deleteAll() async throws
    func cacheSizeBytes() async -> Int64
}

public extension CodableCacheService {
    func get<Value: Codable & Sendable>(key: String) async throws -> Value? {
        try await get(key: key, as: Value.self)
    }

    func update<Value: Codable & Sendable>(
        key: String,
        update: @Sendable (inout Value) -> Void
    ) async throws {
        try await self.update(key: key, as: Value.self, update: update)
    }

    func observe<Value: Codable & Sendable>(key: String) -> AsyncStream<Value> {
        observe(key: key, as: Value.self)
    }
}

public actor DiskCodableCacheService: CodableCacheService {
    public let directory: FileManager.SearchPathDirectory
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private nonisolated let updateSubject = PassthroughSubject<String, Never>()

    public init(directory: FileManager.SearchPathDirectory) {
        self.directory = directory
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public func save<Value: Codable & Sendable>(_ value: Value, key: String) throws {
        try save(value, key: key, expiry: nil)
    }

    public func save<Value: Codable & Sendable>(
        _ value: Value,
        key: String,
        expiry: Date?
    ) throws {
        let cached = CachedObject(expiry: expiry, object: value)
        try save(cached, key: key)
    }

    public func get<Value: Codable & Sendable>(
        key: String,
        as type: Value.Type
    ) throws -> Value? {
        guard let cached: CachedObject<Value> = try cachedObject(key: key) else { return nil }
        if let expiry = cached.expiry, expiry < .now {
            try delete(key: key)
            return nil
        }
        return cached.object
    }

    public func update<Value: Codable & Sendable>(
        key: String,
        as type: Value.Type,
        update: @Sendable (inout Value) -> Void
    ) throws {
        guard var cached: CachedObject<Value> = try cachedObject(key: key) else { return }
        if let expiry = cached.expiry, expiry < .now {
            try delete(key: key)
            return
        }
        update(&cached.object)
        try save(cached, key: key)
    }

    public func contains(key: String) throws -> Bool {
        let url = try fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return false }

        let data = try Data(contentsOf: url)
        let metadata = try decoder.decode(CachedObjectMetadata.self, from: data)
        if let expiry = metadata.expiry, expiry < .now {
            try delete(key: key)
            return false
        }
        return true
    }

    public nonisolated func observe<Value: Codable & Sendable>(
        key: String,
        as type: Value.Type
    ) -> AsyncStream<Value> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                if let value = try? await self.get(key: key, as: type) {
                    continuation.yield(value)
                }
                for await updatedKey in self.updateSubject.values where updatedKey == key {
                    if let value = try? await self.get(key: key, as: type) {
                        continuation.yield(value)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func delete(key: String) throws {
        let url = try fileURL(for: key)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public func deleteAll() throws {
        let directoryURL = try cacheDirectoryURL()
        let urls = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        for url in urls {
            try fileManager.removeItem(at: url)
        }
    }

    public func cacheSizeBytes() -> Int64 {
        guard let directoryURL = try? cacheDirectoryURL() else { return 0 }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator.allObjects {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize
            else { continue }
            total += Int64(fileSize)
        }
        return total
    }

    private func cacheDirectoryURL() throws -> URL {
        guard let baseURL = fileManager.urls(for: directory, in: .userDomainMask).first else {
            throw Failure.unableToFindCacheDirectory
        }

        let url = baseURL.appendingPathComponent("albumo", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fileURL(for key: String) throws -> URL {
        guard !key.isEmpty else { throw Failure.emptyKey }
        let filename = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return try cacheDirectoryURL()
            .appendingPathComponent(filename)
            .appendingPathExtension("json")
    }

    private func cachedObject<Value: Codable & Sendable>(key: String) throws -> CachedObject<Value>? {
        let url = try fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(CachedObject<Value>.self, from: Data(contentsOf: url))
    }

    private func save<Value: Codable & Sendable>(
        _ cached: CachedObject<Value>,
        key: String
    ) throws {
        let data = try encoder.encode(cached)
        try data.write(to: fileURL(for: key), options: .atomic)
        updateSubject.send(key)
    }

    enum Failure: Error {
        case unableToFindCacheDirectory
        case emptyKey
    }
}

private struct CachedObjectMetadata: Decodable {
    let expiry: Date?
}
