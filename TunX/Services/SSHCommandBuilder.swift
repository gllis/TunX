//
//  SSHCommandBuilder.swift
//  TunX
//
//  Created by liguilong on 2026/8/13.
//

import Foundation

struct SSHInvocation {
    let arguments: [String]
    let credential: String?
}

enum SSHCommandBuilderError: Error, LocalizedError {
    case invalidRule

    var errorDescription: String? {
        switch self {
        case .invalidRule:
            return "转发规则不完整"
        }
    }
}

final class SSHCommandBuilder {
    static let sshPath = "/usr/bin/ssh"

    static func build(
        for tunnel: Tunnel,
        password: String? = nil,
        keyPassphrase: String? = nil
    ) throws -> SSHInvocation {
        var args: [String] = [
            "-N",
            "-o", "ServerAliveInterval=60",
            "-o", "ServerAliveCountMax=3",
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
                "-o", "PubkeyAuthentication=no"
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
