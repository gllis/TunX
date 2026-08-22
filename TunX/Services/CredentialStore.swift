//
//  CredentialStore.swift
//  TunX
//
//  Created by glli on 2026/8/21.
//

import Foundation
import CryptoKit
import Security

/// 凭证条目账号，按隧道 ID 区分密码与私钥口令。
enum CredentialAccount {
    static func password(_ id: UUID) -> String { "\(id.uuidString).password" }
    static func keyPassphrase(_ id: UUID) -> String { "\(id.uuidString).keyPassphrase" }
}

/// 密码与私钥口令的本地存储：AES-GCM 加密后写入应用容器，不再使用系统钥匙串。
@MainActor
final class CredentialStore {
    static let shared = CredentialStore()

    private enum Keys {
        static let keychainMigrated = "credentialsMigratedFromKeychain"
    }

    private let directory: URL
    private let storeURL: URL
    private let keyURL: URL
    private var secrets: [String: String] = [:]

    private lazy var encryptionKey: SymmetricKey = loadOrCreateKey()

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        directory = base.appendingPathComponent("TunX", isDirectory: true)
        storeURL = directory.appendingPathComponent("credentials.dat")
        keyURL = directory.appendingPathComponent("credentials.key")

        prepareDirectory()
        secrets = loadSecrets()
        migrateFromKeychainIfNeeded()
    }

    func secret(for account: String) -> String? {
        guard let value = secrets[account], !value.isEmpty else { return nil }
        return value
    }

    /// 传入空值等同于删除该条目。
    func setSecret(_ secret: String?, for account: String) {
        let value = secret ?? ""
        if value.isEmpty {
            guard secrets.removeValue(forKey: account) != nil else { return }
        } else {
            guard secrets[account] != value else { return }
            secrets[account] = value
        }
        persist()
    }

    func removeSecrets(for accounts: [String]) {
        let removed = accounts.compactMap { secrets.removeValue(forKey: $0) }
        guard !removed.isEmpty else { return }
        persist()
    }

    // MARK: - Storage

    private func prepareDirectory() {
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func loadSecrets() -> [String: String] {
        guard let data = try? Data(contentsOf: storeURL), !data.isEmpty else { return [:] }
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            let plain = try AES.GCM.open(box, using: encryptionKey)
            return try JSONDecoder().decode([String: String].self, from: plain)
        } catch {
            print("凭证读取失败: \(error)")
            return [:]
        }
    }

    private func persist() {
        do {
            let plain = try JSONEncoder().encode(secrets)
            guard let combined = try AES.GCM.seal(plain, using: encryptionKey).combined else { return }
            try combined.write(to: storeURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: storeURL.path
            )
        } catch {
            print("凭证保存失败: \(error)")
        }
    }

    private func loadOrCreateKey() -> SymmetricKey {
        if let data = try? Data(contentsOf: keyURL), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        do {
            try key.withUnsafeBytes { Data($0) }.write(to: keyURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: keyURL.path
            )
        } catch {
            print("凭证密钥写入失败: \(error)")
        }
        return key
    }

    // MARK: - Migration

    /// 旧版本把凭证写在系统钥匙串，这里一次性搬到本地并清理钥匙串条目。
    private func migrateFromKeychainIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Keys.keychainMigrated) else { return }
        defer { defaults.set(true, forKey: Keys.keychainMigrated) }

        let service = Bundle.main.bundleIdentifier ?? "com.gllis.TunX"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return
        }

        var imported = false
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data,
                  let value = String(data: data, encoding: .utf8),
                  !value.isEmpty,
                  secrets[account] == nil else {
                continue
            }
            secrets[account] = value
            imported = true
        }

        if imported {
            persist()
        }

        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ] as CFDictionary)
    }
}
