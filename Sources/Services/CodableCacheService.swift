//
//  CodableStorageService.swift
//  AlbumoCore
//
//  Created by BJ Beecher on 3/13/25.
//

@preconcurrency import Combine
import Dependencies
import Foundation
import Models

public protocol CodableCacheService: Sendable {
    func save<T: Cacheable>(_ object: T, id: String, expiry: Date?) async throws
    func save<T: Cacheable>(_ object: T, id: String) async throws
    func update<T: Cacheable>(id: String, update: @Sendable (inout T) -> Void) async throws
    func updateAll<T: Cacheable>(update: @Sendable (inout T) -> Void) async throws
    func exists<T: Cacheable>(id: String, type: T.Type) async throws -> Bool
    func fetch<T: Cacheable>(id: String) async throws -> T?
    func observe<T: Cacheable>(id: String) -> AsyncStream<T>
    func clear<T: Cacheable>(id: String, model: T.Type) async throws
    func clearAll<T: Cacheable>(type: T.Type) async throws
    func clearAll() async throws
    func cacheSizeBytes() async -> Int64
}

actor CodableCacheServiceLiveValue: CodableCacheService {
    let directory: FileManager.SearchPathDirectory
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    nonisolated let updateSubject = PassthroughSubject<(id: String, type: String), Never>()
    
    init(directory: FileManager.SearchPathDirectory) {
        self.directory = directory
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }
    
    private func getDirectoryUrl() throws -> URL {
        guard let url = fileManager.urls(for: directory, in: .userDomainMask).first else {
            throw Failure.unableToFindCachesDirectory
        }
        return url.appendingPathComponent("albumo", isDirectory: true)
    }
    
    private func getModelDirectoryUrl<T>(type: T.Type) throws -> URL {
        let cachesDirectoryUrl = try getDirectoryUrl()
        let typeKey = String(describing: type)
        let directoryUrl = cachesDirectoryUrl.appendingPathComponent(typeKey, isDirectory: true)
        try? fileManager.createDirectory(at: directoryUrl, withIntermediateDirectories: true)
        return directoryUrl
    }
    
    private func createUrl<T: Cacheable>(for id: String, of type: T.Type) throws -> URL {
        let modelDirectory = try getModelDirectoryUrl(type: CachedObject<T>.self)
        return modelDirectory.appendingPathComponent(id).appendingPathExtension("json")
    }
    
    func save<T: Cacheable>(_ object: T, id: String) throws {
        try save(object, id: id, expiry: nil)
    }
    
    func save<T: Cacheable>(_ object: T, id: String, expiry: Date?) throws {
        let cached = CachedObject(expiry: expiry, object: object)
        try save(cached, id: id)
    }
    
    func save<T: Cacheable>(_ object: CachedObject<T>, id: String) throws {
        let url = try createUrl(for: id, of: T.self)
        let data = try encoder.encode(object)
        try data.write(to: url, options: .atomic)
        
        updateSubject.send((id: id, type: String(describing: T.self)))
    }
    
    func fetch<T: Cacheable>(id: String) throws -> T? {
        guard let cached: CachedObject<T> = try fetchCachedObject(id: id) else { return nil }
        return cached.object
    }
    
    private func fetchCachedObject<T: Cacheable>(id: String) throws -> CachedObject<T>? {
        let url = try createUrl(for: id, of: T.self)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let cachedObject = try decoder.decode(CachedObject<T>.self, from: data)
        if let expiry = cachedObject.expiry, expiry < .now {
            try clear(id: id, model: T.self)
            return nil
        }
        return cachedObject
    }
    
    func update<T: Cacheable>(id: String, update: (inout T) -> Void) async throws {
        guard var cached: CachedObject<T> = try fetchCachedObject(id: id) else { return }
        update(&cached.object)
        try save(cached, id: id)
    }
    
    func updateAll<T: Cacheable>(update: (inout T) -> Void) async throws {
        let modelDirectory = try getModelDirectoryUrl(type: T.self)
        let urls = try fileManager.contentsOfDirectory(at: modelDirectory, includingPropertiesForKeys: nil)
        for url in urls {
            let id = url.deletingPathExtension().lastPathComponent
            let data = try Data(contentsOf: url)
            var cached = try decoder.decode(CachedObject<T>.self, from: data)
            update(&cached.object)
            try save(cached, id: id)
        }
    }
    
    func exists<T: Cacheable>(id: String, type: T.Type) async throws -> Bool {
        let url = try createUrl(for: id, of: T.self)
        return fileManager.fileExists(atPath: url.path)
    }
    
    func clear<T: Cacheable>(id: String, model: T.Type) throws {
        let url = try createUrl(for: id, of: T.self)
        try? fileManager.removeItem(at: url)
    }
    
    func clearAll<T: Cacheable>(type: T.Type) async throws {
        let modelDirectory = try getModelDirectoryUrl(type: type)
        let urls = try fileManager.contentsOfDirectory(at: modelDirectory, includingPropertiesForKeys: nil)
        for url in urls { try fileManager.removeItem(at: url) }
    }
    
    func clearAll() throws {
        let cachesUrl = try getDirectoryUrl()
        let urls = try fileManager.contentsOfDirectory(at: cachesUrl, includingPropertiesForKeys: nil)
        for url in urls { try fileManager.removeItem(at: url) }
    }

    func cacheSizeBytes() async -> Int64 {
        guard let url = try? getDirectoryUrl(), fileManager.fileExists(atPath: url.path) else { return 0 }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator.allObjects {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize else {
                continue
            }
            total += Int64(fileSize)
        }

        return total
    }
    
    // MARK: - Observation
    nonisolated func observe<T: Cacheable>(id: String) -> AsyncStream<T> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                if let object: T = try? await self.fetch(id: id) { continuation.yield(object) }
                for await (objectId, typeKey) in self.updateSubject.values
                    where objectId == id && typeKey == String(describing: T.self) {
                    if let object: T = try? await self.fetch(id: id) {
                        continuation.yield(object)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    
    // MARK: - Errors
    enum Failure: Error {
        case unableToFindCachesDirectory
        case recordNotFound
    }
}

final class CodableCachServicePreviewValue: CodableCacheService {
    func save<T>(_ object: T, id: String) async throws where T : Models.Cacheable {}
    func save<T: Cacheable>(_ object: T, id: String, expiry: Date?) async throws {}
    func update<T: Cacheable>(id: String, update: (inout T) -> Void) async throws {}
    func updateAll<T: Cacheable>(update: (inout T) -> Void) async throws {}
    func exists<T: Cacheable>(id: String, type: T.Type) async throws -> Bool { true }
    func fetch<T: Cacheable>(id: String) async throws -> T? { .sample }
    func observe<T: Cacheable>(id: String) -> AsyncStream<T> { AsyncStream { .sample } }
    func clear<T: Cacheable>(id: String, model: T.Type) async throws {}
    func clearAll<T: Cacheable>(type: T.Type) async throws {}
    func clearAll() async throws {}
    func cacheSizeBytes() async -> Int64 { 0 }
}

public enum CodableStorageServiceKey: DependencyKey {
    public static let liveValue: CodableCacheService = CodableCacheServiceLiveValue(directory: .documentDirectory)
    public static let previewValue: CodableCacheService = CodableCachServicePreviewValue()
}

public extension DependencyValues {
    var codableStorageService: CodableCacheService {
        get { self[CodableStorageServiceKey.self] }
        set { self[CodableStorageServiceKey.self] = newValue }
    }
}
