import Foundation

struct StoredQuery<Value: Codable & Sendable>: Codable, Sendable {
    var value: Value
    var updatedAt: Date
    var isInvalidated: Bool

    init(value: Value, updatedAt: Date, isInvalidated: Bool = false) {
        self.value = value
        self.updatedAt = updatedAt
        self.isInvalidated = isInvalidated
    }
}

public protocol QueryStorage: Sendable {
    func get<Value: Codable & Sendable>(key: String, as type: Value.Type) async throws -> Value?
    func save<Value: Codable & Sendable>(_ value: Value, key: String) async throws
    func delete(key: String) async throws
}
