//
//  KeychainStore.swift
//  JamfCommander
//
//  Keychain-backed storage for the app's API credentials.
//

import Foundation
import Security

/// A minimal wrapper over the macOS Keychain for the credentials this app holds.
///
/// Items are stored as generic passwords under the app's bundle identifier, readable only while the
/// Mac is unlocked, and never synchronised to iCloud.
///
/// Credentials must not live in `UserDefaults`. A preferences plist sits in the user's Library in
/// clear and is readable by anything running as that user; the values kept here are working API
/// credentials for a production Jamf instance, and — from the Apple Business Manager work — a
/// private key with no read-only scope available to constrain it.
enum KeychainStore {

    /// The secrets this app stores. The raw value is the Keychain account name, so changing one
    /// orphans the existing item rather than renaming it.
    enum Key: String, CaseIterable {
        case jamfClientId = "jamf.clientId"
        case jamfClientSecret = "jamf.clientSecret"
    }

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let detail = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
                return "Keychain access failed: \(detail)"
            case .invalidData:
                return "A stored credential could not be read and may be corrupted."
            }
        }
    }

    /// All items are scoped to the app's bundle identifier so they cannot collide with another app's.
    private static let service = Bundle.main.bundleIdentifier ?? "com.marcoliff.JamfCommander"

    // MARK: - Read

    /// The stored value, or `nil` when no item exists. An empty stored string is treated as absent,
    /// matching how the rest of the app treats a blank credential.
    static func string(for key: Key) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.invalidData }
            guard let value = String(data: data, encoding: .utf8) else { throw KeychainError.invalidData }
            return value.isEmpty ? nil : value
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Write

    /// Stores a value, replacing any existing item. Passing `nil` or an empty string removes the
    /// item, so clearing a credential leaves nothing behind rather than an empty entry.
    static func set(_ value: String?, for key: Key) throws {
        guard let value, !value.isEmpty else {
            try remove(key)
            return
        }

        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidData }

        let updateStatus = SecItemUpdate(
            baseQuery(for: key) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery(for: key)
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    /// Removes a single item. A missing item is not an error — the end state is the same.
    static func remove(_ key: Key) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Removes every credential this app owns. Used by "Clear All" in the configuration sheet.
    static func removeAll() throws {
        for key in Key.allCases {
            try remove(key)
        }
    }

    // MARK: - Helpers

    /// The attributes that identify one item. `kSecAttrSynchronizable` is explicitly false so these
    /// never reach iCloud Keychain, and so lookups match only the local item.
    private static func baseQuery(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrSynchronizable as String: false
        ]
    }
}
