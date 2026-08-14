//
//  Tunnel.swift
//  TunX
//
//  Created by liguilong on 2026/8/13.
//

import Foundation
import SwiftData

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

@Model
final class Tunnel {
    @Attribute(.unique) var id: UUID
    var name: String
    var host: String
    var port: Int
    var user: String
    var authMethodRaw: String
    var identityFilePath: String?
    var extraOptions: String
    var autoReconnect: Bool
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

    var destination: String {
        user.isEmpty ? host : "\(user)@\(host)"
    }

    var displayName: String {
        name.isEmpty ? destination : name
    }
}
