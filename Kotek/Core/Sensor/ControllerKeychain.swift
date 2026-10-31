//
//  ControllerKeychain.swift
//  Kotek
//
//  A controller's secrets, by hardware ID: the owner key this phone handed it
//  when it set the PIN, and the PIN as last typed. In iCloud Keychain
//  (synchronizable), so they follow the Apple ID to a new iPhone or an iPad —
//  not the Gomelan account, which is a guest that a reinstall throws away.
//
//  Not `Defaults`: the owner key is the only proof of ownership short of
//  opening the enclosure and holding BOOT.
//

import Foundation
import Security

nonisolated enum ControllerKeychain {
    enum Item: String {
        case ownerKey = "controller.owner-key"
        case pin = "controller.pin"
    }

    static func read(_ item: Item, for hardwareID: String) -> Data? {
        var query = base(item, hardwareID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func save(_ data: Data, _ item: Item, for hardwareID: String) {
        let query = base(item, hardwareID)
        let update = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            // Synchronizable items can't be ThisDeviceOnly.
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete(_ item: Item, for hardwareID: String) {
        SecItemDelete(base(item, hardwareID) as CFDictionary)
    }

    private static func base(_ item: Item, _ hardwareID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.rawValue,
            kSecAttrAccount as String: hardwareID,
            kSecAttrSynchronizable as String: true
        ]
    }
}
