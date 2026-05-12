import Foundation

@propertyWrapper
public struct KeychainItem<T: Codable> {
    private let key: String
    private let keychainService: KeychainClient

    public init(_ forKey: String, keychainService: KeychainClient = .init()) {
        self.key = forKey
        self.keychainService = keychainService
        wrappedValue = try? keychainService.value(forKey: key)
    }

    public var wrappedValue: T? {
        willSet {
            if let item = newValue {
                try? keychainService.save(item, forKey: key)
            } else {
                try? keychainService.deleteValue(forKey: key)
            }
        }
    }
}
