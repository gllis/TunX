//
//  Tunnel.swift
//  TunX
//
//  Created by glli on 2026/8/13.
//

import Foundation
import SwiftData

/// SSH 认证方式。
enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case password = "password"
    case identityFile = "identityFile"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .password: return "密码"
        case .identityFile: return "私钥文件"
        }
    }
}

/// 一条 SSH 隧道配置（主机、认证、转发规则与自动重连策略）。
@Model
final class Tunnel {
    @Attribute(.unique) var id: UUID
    var name: String
    var host: String
    var port: Int
    var user: String
    /// 以字符串持久化，避免 SwiftData 直接存储枚举。
    var authMethodRaw: String
    var identityFilePath: String?
    /// 沙盒下访问用户所选私钥文件所需的安全作用域书签。
    var identityBookmarkData: Data?
    /// 附加传给 ssh 的选项，空格分隔。
    var extraOptions: String
    var autoReconnect: Bool
    /// 自动重连间隔（秒）。
    var reconnectDelay: Int
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ForwardRule.tunnel)
    var rules: [ForwardRule]

    init(
        name: String = "",
        host: String = "",
        port: Int = 22,
        user: String = "",
        authMethod: AuthMethod = .identityFile,
        identityFilePath: String? = nil,
        identityBookmarkData: Data? = nil,
        extraOptions: String = "",
        autoReconnect: Bool = true,
        reconnectDelay: Int = 5,
        rules: [ForwardRule] = []
    ) {
        self.id = UUID()
        self.name = name
        self.host = host
        self.port = port
        self.user = user
        self.authMethodRaw = authMethod.rawValue
        self.identityFilePath = identityFilePath
        self.identityBookmarkData = identityBookmarkData
        self.extraOptions = extraOptions
        self.autoReconnect = autoReconnect
        self.reconnectDelay = reconnectDelay
        self.createdAt = Date()
        self.updatedAt = Date()
        self.rules = rules
    }
}

extension Tunnel {
    var authMethod: AuthMethod {
        get { AuthMethod(rawValue: authMethodRaw) ?? .identityFile }
        set { authMethodRaw = newValue.rawValue }
    }

    /// `user@host`，用户名为空时仅返回主机。
    var destination: String {
        user.isEmpty ? host : "\(user)@\(host)"
    }

    /// 列表与菜单中展示的名称；未填写名称时回退到目标地址。
    var displayName: String {
        name.isEmpty ? destination : name
    }
}
