import Foundation
import Security
import Testing
@testable import VLKeychain

@Test
func keychainClientIncludesSharedItemAttributes() throws {
    var insertedAttributes: [String: Any] = [:]
    let client = KeychainClient(
        addItem: { attributes, _ in
            insertedAttributes = attributes as NSDictionary as? [String: Any] ?? [:]
            return errSecSuccess
        },
        updateItem: { _, _ in errSecSuccess },
        fetchItem: { _, _ in errSecItemNotFound },
        deleteItem: { _ in errSecSuccess },
        encoder: JSONEncoder(),
        decoder: JSONDecoder(),
        accessGroup: "ABCDE12345.com.example.shared",
        service: "example.session",
        accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    )

    try client.insert("token", forKey: "session")

    #expect(insertedAttributes[kSecAttrAccount as String] as? String == "session")
    #expect(
        insertedAttributes[kSecAttrAccessGroup as String] as? String ==
            "ABCDE12345.com.example.shared"
    )
    #expect(insertedAttributes[kSecAttrService as String] as? String == "example.session")
    #expect(
        insertedAttributes[kSecAttrAccessible as String] as? String ==
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    )
}
