//
//  TunnelManager.swift
//  TunX
//
//  Created by liguilong on 2026/8/13.
//

import Foundation
import Combine
import SwiftUI

enum TunnelState: String {
    case stopped
    case starting
    case running
    case stopping
    case reconnecting
    case error
}

extension TunnelState {
    var label: String {
        switch self {
        case .stopped: return "已停止"
        case .starting: return "启动中"
        case .running: return "运行中"
        case .stopping: return "停止中"
        case .reconnecting: return "重连中"
        case .error: return "错误"
        }
    }

    var color: Color {
        switch self {
        case .stopped:
            return Color.secondary
        case .starting, .stopping, .reconnecting:
            return Color.orange
        case .running:
            return Color.green
        case .error:
            return Color.red
        }
    }
}

struct TunnelStatus {
    let tunnelID: UUID
    var state: TunnelState = .stopped
    var lastError: String?
    var log: String = ""
    var pid: Int32?
    var nextReconnect: Date?
}

enum KeychainAccount {
    static func password(_ id: UUID) -> String { "\(id.uuidString).password" }
    static func keyPassphrase(_ id: UUID) -> String { "\(id.uuidString).keyPassphrase" }
}

private struct RunningSession {
    let process: Process
    let tunnel: Tunnel
    let credentialURL: URL?
    let identityURL: URL?
    var manuallyStopped: Bool = false

    func cleanup() {
        if let url = identityURL {
            url.stopAccessingSecurityScopedResource()
        }
        if let url = credentialURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

@MainActor
final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()

    @Published private(set) var statuses: [UUID: TunnelStatus] = [:]

    private var sessions: [UUID: RunningSession] = [:]
    private var reconnectTasks: [UUID: Task<Void, Never>] = [:]
    private let maxLogLines = 500

    private init() {}

    // MARK: - Public API

    func status(for tunnel: Tunnel) -> TunnelStatus {
        statuses[tunnel.id] ?? TunnelStatus(tunnelID: tunnel.id)
    }

    func isRunning(_ tunnel: Tunnel) -> Bool {
        let state = status(for: tunnel).state
        return state == .running || state == .starting || state == .reconnecting
    }

    func toggle(_ tunnel: Tunnel) {
        if isRunning(tunnel) {
            stop(tunnel)
        } else {
            start(tunnel)
        }
    }

    func start(_ tunnel: Tunnel) {
        guard sessions[tunnel.id] == nil else { return }
        cancelReconnect(for: tunnel.id)

        updateStatus(id: tunnel.id, state: .starting)

        var identityURL: URL?
        var credentialURL: URL?

        do {
            let password: String? = {
                guard tunnel.authMethod == .password else { return nil }
                return KeychainManager.shared.readPassword(account: KeychainAccount.password(tunnel.id))
            }()

            let keyPassphrase: String? = {
                guard tunnel.authMethod == .identityFile else { return nil }
                return KeychainManager.shared.readPassword(account: KeychainAccount.keyPassphrase(tunnel.id))
            }()

            let invocation = try SSHCommandBuilder.build(
                for: tunnel,
                password: password,
                keyPassphrase: keyPassphrase
            )

            var environment = ProcessInfo.processInfo.environment

            // 安全作用域书签：启动前开始访问私钥文件
            if tunnel.authMethod == .identityFile,
               let bookmarkData = tunnel.identityBookmarkData {
                identityURL = try SecurityScopedBookmark.resolve(bookmarkData)
                _ = identityURL?.startAccessingSecurityScopedResource()
            }

            // 凭证通过 Bundle 内的 askpass 脚本 + 临时文件注入
            if let credential = invocation.credential, !credential.isEmpty {
                guard let askpassScript = Bundle.main.url(forResource: "askpass", withExtension: "sh") else {
                    throw SSHCommandBuilderError.invalidRule
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("tunx-cred-\(UUID().uuidString).txt")
                try credential.write(to: url, atomically: true, encoding: .utf8)
                environment["TUNX_SSH_ASKPASS_FILE"] = url.path
                environment["SSH_ASKPASS"] = askpassScript.path
                environment["SSH_ASKPASS_REQUIRE"] = "force"
                environment["DISPLAY"] = ":0"
                credentialURL = url
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: SSHCommandBuilder.sshPath)
            process.arguments = invocation.arguments
            process.environment = environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let session = RunningSession(
                process: process,
                tunnel: tunnel,
                credentialURL: credentialURL,
                identityURL: identityURL
            )
            let tunnelID = tunnel.id
            sessions[tunnelID] = session

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let self = self,
                      let text = String(data: data, encoding: .utf8),
                      !text.isEmpty else { return }
                Task { @MainActor [tunnelID] in
                    self.appendLog(id: tunnelID, text: text)
                }
            }

            process.terminationHandler = { [weak self] process in
                Task { @MainActor [tunnelID] in
                    self?.handleTermination(tunnelID: tunnelID, exitCode: Int(process.terminationStatus))
                }
            }

            try process.run()
            updateStatus(id: tunnelID, state: .running, pid: process.processIdentifier)
            appendLog(id: tunnelID, text: "[TunX] 启动 ssh (pid: \(process.processIdentifier))\n")
            appendLog(id: tunnelID, text: "[TunX] 命令: ssh \(invocation.arguments.joined(separator: " "))\n")
        } catch {
            identityURL?.stopAccessingSecurityScopedResource()
            if let url = credentialURL {
                try? FileManager.default.removeItem(at: url)
            }
            updateStatus(id: tunnel.id, state: .error, lastError: error.localizedDescription)
            appendLog(id: tunnel.id, text: "[TunX] 启动失败: \(error.localizedDescription)\n")
        }
    }

    func stop(_ tunnel: Tunnel) {
        guard let session = sessions[tunnel.id] else {
            cancelReconnect(for: tunnel.id)
            updateStatus(id: tunnel.id, state: .stopped)
            return
        }
        var updated = session
        updated.manuallyStopped = true
        sessions[tunnel.id] = updated
        updateStatus(id: tunnel.id, state: .stopping)
        session.process.terminate()
        appendLog(id: tunnel.id, text: "[TunX] 用户请求停止\n")
    }

    func stopAll() {
        for session in sessions.values {
            session.process.terminate()
        }
        for task in reconnectTasks.values {
            task.cancel()
        }
        reconnectTasks.removeAll()
    }

    func clearKeychainItems(for tunnel: Tunnel) {
        try? KeychainManager.shared.deletePassword(account: KeychainAccount.password(tunnel.id))
        try? KeychainManager.shared.deletePassword(account: KeychainAccount.keyPassphrase(tunnel.id))
    }

    func generatedCommand(for tunnel: Tunnel) -> String {
        do {
            let invocation = try SSHCommandBuilder.build(for: tunnel)
            return "ssh \(invocation.arguments.joined(separator: " "))"
        } catch {
            return "无法生成命令: \(error.localizedDescription)"
        }
    }

    // MARK: - Private

    private func handleTermination(tunnelID: UUID, exitCode: Int) {
        guard let session = sessions[tunnelID] else { return }
        session.cleanup()
        sessions.removeValue(forKey: tunnelID)

        if session.manuallyStopped {
            updateStatus(id: tunnelID, state: .stopped)
            appendLog(id: tunnelID, text: "[TunX] 已停止\n")
            return
        }

        let errorMessage = exitCode == 0 ? "连接已断开" : "ssh 退出码 \(exitCode)"
        appendLog(id: tunnelID, text: "[TunX] \(errorMessage)\n")

        let tunnel = session.tunnel
        guard tunnel.autoReconnect else {
            updateStatus(id: tunnelID, state: .error, lastError: errorMessage)
            return
        }

        let delay = max(1, tunnel.reconnectDelay)
        let nextAttempt = Date().addingTimeInterval(TimeInterval(delay))
        updateStatus(id: tunnelID, state: .reconnecting, lastError: errorMessage, nextReconnect: nextAttempt)
        appendLog(id: tunnelID, text: "[TunX] 将在 \(delay) 秒后自动重连…\n")

        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * NSEC_PER_SEC)
            guard let self = self, self.sessions[tunnelID] == nil else { return }
            self.start(tunnel)
        }
        reconnectTasks[tunnelID] = task
    }

    private func cancelReconnect(for tunnelID: UUID) {
        reconnectTasks[tunnelID]?.cancel()
        reconnectTasks.removeValue(forKey: tunnelID)
    }

    private func updateStatus(
        id: UUID,
        state: TunnelState,
        lastError: String? = nil,
        pid: Int32? = nil,
        nextReconnect: Date? = nil
    ) {
        var status = statuses[id] ?? TunnelStatus(tunnelID: id)
        status.state = state
        if let lastError = lastError { status.lastError = lastError }
        if let pid = pid { status.pid = pid }
        if let nextReconnect = nextReconnect { status.nextReconnect = nextReconnect }
        statuses[id] = status
    }

    private func appendLog(id: UUID, text: String) {
        var status = statuses[id] ?? TunnelStatus(tunnelID: id)
        status.log.append(text)
        var lines = status.log.components(separatedBy: "\n")
        if lines.count > maxLogLines {
            lines = Array(lines.suffix(maxLogLines))
            status.log = lines.joined(separator: "\n")
        }
        statuses[id] = status
    }
}
