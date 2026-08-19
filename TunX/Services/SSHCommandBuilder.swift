//
//  SSHCommandBuilder.swift
//  TunX
//
//  Created by glli on 2026/8/13.
//

import Foundation

struct SSHInvocation {
    let arguments: [String]
    /// 供 SSH_ASKPASS 读取的密码或私钥口令；无凭证时为 nil。
    let credential: String?
}

enum SSHCommandBuilderError: Error, LocalizedError {
    /// 转发规则缺少必要端口或主机。
    case invalidRule

    var errorDescription: String? {
        switch self {
        case .invalidRule:
            return "转发规则不完整"
        }
    }
}

/// 根据隧道配置生成 OpenSSH 参数。
final class SSHCommandBuilder {
    static let sshPath = "/usr/bin/ssh"

    static func build(
        for tunnel: Tunnel,
        password: String? = nil,
        keyPassphrase: String? = nil
    ) throws -> SSHInvocation {
        let aliveInterval = AppSettings.sshServerAliveInterval
        let aliveCountMax = AppSettings.sshServerAliveCountMax
        var args: [String] = [
            "-N", // 只做端口转发，不打开远程 shell
            "-o", "ServerAliveInterval=\(aliveInterval)",
            "-o", "ServerAliveCountMax=\(aliveCountMax)",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "BatchMode=no"
        ]

        if tunnel.port != 22 {
            args += ["-p", String(tunnel.port)]
        }

        var credential: String?

        switch tunnel.authMethod {
        case .identityFile:
            if let path = tunnel.identityFilePath, !path.isEmpty {
                args += ["-i", path]
            }
            credential = keyPassphrase
        case .password:
            args += [
                "-o", "PreferredAuthentications=password",
                "-o", "PubkeyAuthentication=no",
                "-o", "NumberOfPasswordPrompts=1"
            ]
            credential = password
        }

        for rule in tunnel.rules {
            let flag = try forwardFlag(for: rule)
            args += [flag.0, flag.1]
        }

        if !tunnel.extraOptions.isEmpty {
            args += tokenize(tunnel.extraOptions)
        }

        // 指向真实主目录的 known_hosts，保持与系统 OpenSSH 主机密钥一致
        let knownHosts = "\(realHomeDirectory())/.ssh/known_hosts"
        args += ["-o", "UserKnownHostsFile=\(knownHosts)"]

        args += [tunnel.destination]

        return SSHInvocation(arguments: args, credential: credential)
    }

    private static func forwardFlag(for rule: ForwardRule) throws -> (String, String) {
        switch rule.type {
        case .local:
            guard rule.localPort > 0, rule.remotePort > 0 else {
                throw SSHCommandBuilderError.invalidRule
            }
            let local = rule.localHost.isEmpty ? "\(rule.localPort)" : "\(rule.localHost):\(rule.localPort)"
            let remote = "\(rule.remoteHost):\(rule.remotePort)"
            return ("-L", "\(local):\(remote)")
        case .remote:
            guard rule.localPort > 0, rule.remotePort > 0 else {
                throw SSHCommandBuilderError.invalidRule
            }
            // -R 的绑定地址在远端，目标地址在本地侧
            let remoteBind = rule.localHost.isEmpty ? "\(rule.localPort)" : "\(rule.localHost):\(rule.localPort)"
            let localTarget = "\(rule.remoteHost):\(rule.remotePort)"
            return ("-R", "\(remoteBind):\(localTarget)")
        case .dynamic:
            guard rule.localPort > 0 else {
                throw SSHCommandBuilderError.invalidRule
            }
            let bind = rule.localHost.isEmpty ? "\(rule.localPort)" : "\(rule.localHost):\(rule.localPort)"
            return ("-D", bind)
        }
    }

    /// 将用户填写的额外选项按 shell 规则拆成参数（支持引号与转义）。
    static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var escapeNext = false

        for char in input {
            if escapeNext {
                current.append(char)
                escapeNext = false
                continue
            }
            if char == "\\" {
                escapeNext = true
                continue
            }
            if char == "\"" {
                inQuotes.toggle()
                continue
            }
            if char.isWhitespace && !inQuotes {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            current.append(char)
        }

        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
