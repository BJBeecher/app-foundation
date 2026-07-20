import Foundation

public actor UserDefaultsService: @unchecked Sendable {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let defaults = UserDefaults.standard

    public init() {}

    public func save<Value: Codable>(_ value: Value, forKey key: String) throws {
        let data = try encoder.encode(value)
        defaults.set(data, forKey: key)
    }

    public func value<Value: Codable>(forKey key: String) throws -> Value? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try decoder.decode(Value.self, from: data)
    }
}
