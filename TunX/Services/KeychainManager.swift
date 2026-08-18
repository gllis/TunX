//
//  KeychainManager.swift
//  TunX
//
//  Created by glli on 2026/8/13.
//

import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "钥匙串中未找到该项目"
        case .duplicateItem:
            return "钥匙串中已存在该项目"
        case .unexpectedStatus(let status):
            return "钥匙串操作失败（状态码 \(status)）"
        case .invalidData:
            return "无法读取钥匙串数据"
        }
    }
}

/// 使用 Generic Password 存取隧道密码与私钥口令。
final class KeychainManager {
    static let shared = KeychainManager()

    private let service: String

    private init() {
        service = Bundle.main.bundleIdentifier ?? "com.gllis.TunX"
    }

    func savePassword(_ password: String, account: String, label: String? = nil) throws {
        // 先删后加，避免钥匙串重复项
        try deletePassword(account: account)

        guard let data = password.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // 解锁后可读取，便于开机后自动重连
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if let label = label {
            query[kSecAttrLabel as String] = label
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func readPassword(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func deletePassword(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
