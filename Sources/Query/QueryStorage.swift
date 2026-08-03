import Foundation

struct StoredQuery<Value: Codable & Sendable>: Codable, Sendable {
    var value: Value
    var updatedAt: Date
    var isInvalidated = false
}

public protocol QueryStorage: Sendable {
    func get<Value: Codable & Sendable>(key: String, as type: Value.Type) async throws -> Value?
    func save<Value: Codable & Sendable>(_ value: Value, key: String) async throws
    func delete(key: String) async throws
}
