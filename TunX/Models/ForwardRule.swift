//
//  ForwardRule.swift
//  TunX
//
//  Created by glli on 2026/8/13.
//

import Foundation
import SwiftData

/// SSH 端口转发类型，对应 OpenSSH 的 `-L` / `-R` / `-D`。
enum ForwardType: String, Codable, CaseIterable, Identifiable {
    case local = "local"
    case remote = "remote"
    case dynamic = "dynamic"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: return "本地转发 (-L)"
        case .remote: return "远程转发 (-R)"
        case .dynamic: return "动态 SOCKS (-D)"
        }
    }

    var systemImage: String {
        switch self {
        case .local: return "arrow.right.circle"
        case .remote: return "arrow.left.circle"
        case .dynamic: return "globe"
        }
    }
}

/// 单条转发规则。远程转发时 `localHost`/`localPort` 表示远端绑定地址。
@Model
final class ForwardRule {
    var id: UUID
    /// 以字符串持久化转发类型。
    var typeRaw: String
    var localHost: String
    var localPort: Int
    var remoteHost: String
    var remotePort: Int

    var tunnel: Tunnel?

    init(
        type: ForwardType = .local,
        localHost: String = "127.0.0.1",
        localPort: Int = 0,
        remoteHost: String = "",
        remotePort: Int = 0,
        tunnel: Tunnel? = nil
    ) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.localHost = localHost
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.tunnel = tunnel
    }
}

extension ForwardRule {
    var type: ForwardType {
        get { ForwardType(rawValue: typeRaw) ?? .local }
        set { typeRaw = newValue.rawValue }
    }

    var localAddress: String {
        "\(localHost):\(localPort)"
    }
}
