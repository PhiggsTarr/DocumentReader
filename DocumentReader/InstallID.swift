//
//  InstallID.swift
//  DocumentReader
//
//  Created by Gboinyee Tarr on 2/21/26.
//


import Foundation
import Security

enum InstallID {
    private static let service = "com.nerdinventions.DocumentReader"
    private static let account = "install_id_v1"

    static func getOrCreate() -> String {
        if let existing = read() { return existing }
        let fresh = UUID().uuidString.lowercased()
        _ = save(fresh)
        return fresh
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8),
              !str.isEmpty
        else { return nil }

        return str
    }

    private static func save(_ value: String) -> Bool {
        let data = Data(value.utf8)

        // Upsert
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            return SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecSuccess
        } else {
            var addQuery = query
            addQuery.merge(attrs) { _, new in new }
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
    }
}