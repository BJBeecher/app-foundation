import Foundation
import Security

public final class KeychainClient {
    public typealias AddItem = (_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    public typealias UpdateItem = (_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus
    public typealias FetchItem = (_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    public typealias DeleteItem = (_ query: CFDictionary) -> OSStatus

    let addItem: AddItem
    let updateItem: UpdateItem
    let fetchItem: FetchItem
    let deleteItem: DeleteItem

    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init(
        addItem: @escaping AddItem,
        updateItem: @escaping UpdateItem,
        fetchItem: @escaping FetchItem,
        deleteItem: @escaping DeleteItem,
        encoder: JSONEncoder,
        decoder: JSONDecoder
    ) {
        self.addItem = addItem
        self.updateItem = updateItem
        self.fetchItem = fetchItem
        self.deleteItem = deleteItem
        self.encoder = encoder
        self.decoder = decoder
    }

    public convenience init() {
        self.init(
            addItem: SecItemAdd,
            updateItem: SecItemUpdate,
            fetchItem: SecItemCopyMatching,
            deleteItem: SecItemDelete,
            encoder: .init(),
            decoder: .init()
        )
    }
}

public extension KeychainClient {
    func insert<Value: Codable>(_ value: Value, forKey key: String) throws {
        let data = try encoder.encode(value)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]

        let status = addItem(query as CFDictionary, nil)

        switch status {
        case errSecDuplicateItem:
            try updateValue(with: value, forKey: key)
        case errSecSuccess:
            return
        default:
            throw KeychainFailure.badStatus(status)
        }
    }

    func save<Value: Codable>(_ value: Value, forKey key: String) throws {
        do {
            try insert(value, forKey: key)
        } catch let error as KeychainFailure {
            guard case .badStatus(let status) = error, status == errSecDuplicateItem else {
                throw error
            }

            try updateValue(with: value, forKey: key)
        } catch {
            throw error
        }
    }

    func updateValue<Value: Codable>(with newValue: Value, forKey key: String) throws {
        let newData = try encoder.encode(newValue)
        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        let updateQuery: [String: Any] = [
            kSecValueData as String: newData,
        ]

        let status = updateItem(searchQuery as CFDictionary, updateQuery as CFDictionary)

        if status != errSecSuccess {
            throw KeychainFailure.badStatus(status)
        }
    }

    func value<Value: Codable>(forKey key: String) throws -> Value? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]

        var item: CFTypeRef?
        let status = fetchItem(query as CFDictionary, &item)

        switch status {
        case errSecItemNotFound:
            return nil
        case errSecSuccess:
            let dict = item as? [String: Any]
            guard let data = dict?[kSecValueData as String] as? Data else {
                return nil
            }
            return try decoder.decode(Value.self, from: data)
        default:
            throw KeychainFailure.badStatus(status)
        }
    }

    func deleteValue(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]

        let status = deleteItem(query as CFDictionary)

        if status != errSecSuccess {
            throw KeychainFailure.badStatus(status)
        }
    }

    subscript<Value: Codable>(key: String) -> Value? {
        get {
            try? value(forKey: key)
        }
        set {
            if let value = newValue {
                try? insert(value, forKey: key)
            } else {
                try? deleteValue(forKey: key)
            }
        }
    }
}
