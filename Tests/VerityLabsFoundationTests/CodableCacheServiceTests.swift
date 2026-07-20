import Foundation
import Testing
import VLCache

private struct CachedTestValue: Codable, Sendable, Equatable {
    let name: String
    let count: Int
}

@Test
func testCodableCacheStoresValuesByKey() async throws {
    let cache = DiskCodableCacheService(directory: .cachesDirectory)
    let key = "test/value/\(UUID().uuidString)"
    let expected = CachedTestValue(name: "Dinner", count: 3)

    try await cache.save(expected, key: key)
    let value: CachedTestValue? = try await cache.get(key: key)

    #expect(value == expected)
    #expect(try await cache.contains(key: key))

    try await cache.delete(key: key)
    #expect(try await cache.contains(key: key) == false)
}

@Test
func testCodableCacheReplacesAKeyWithoutTypeDirectories() async throws {
    let cache = DiskCodableCacheService(directory: .cachesDirectory)
    let key = "test/replacement/\(UUID().uuidString)"

    try await cache.save(CachedTestValue(name: "Original", count: 1), key: key)
    try await cache.save("Replacement", key: key)

    let value: String? = try await cache.get(key: key)
    #expect(value == "Replacement")

    try await cache.delete(key: key)
}

@Test
func testCodableCacheDeletesExpiredValues() async throws {
    let cache = DiskCodableCacheService(directory: .cachesDirectory)
    let key = "test/expired/\(UUID().uuidString)"

    try await cache.save("Expired", key: key, expiry: .distantPast)
    let value: String? = try await cache.get(key: key)

    #expect(value == nil)
    #expect(try await cache.contains(key: key) == false)
}
