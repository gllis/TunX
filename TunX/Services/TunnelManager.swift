//
//  TunnelManager.swift
//  TunX
//
//  Created by glli on 2026/8/13.
//

import Foundation
import Combine
import SwiftUI
import Darwin

/// 隧道运行状态。
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

    /// 启动中、运行中、重连中视为“占用中”，用于状态栏与启停按钮。
    var isActive: Bool {
        switch self {
        case .running, .starting, .reconnecting:
            return true
        case .stopped, .stopping, .error:
            return false
        }
    }
}

/// 单条隧道的运行时状态（不写入 SwiftData）。
struct TunnelStatus {
    let tunnelID: UUID
    var state: TunnelState = .stopped
    var lastError: String?
    var log: String = ""
    var pid: Int32?
    var nextReconnect: Date?
}

/// 启动 ssh 前可预知的失败原因。
enum TunnelLaunchError: Error, LocalizedError {
    case missingPassword

    var errorDescription: String? {
        switch self {
        case .missingPassword:
            return "请先填写密码"
        }
    }
}

/// 钥匙串条目账号，按隧道 ID 区分密码与私钥口令。
enum KeychainAccount {
    static func password(_ id: UUID) -> String { "\(id.uuidString).password" }
    static func keyPassphrase(_ id: UUID) -> String { "\(id.uuidString).keyPassphrase" }
}

/// 正在运行的 ssh 进程及其沙盒资源。
private struct RunningSession {
    let process: Process
    let tunnel: Tunnel
    let outputPipe: Pipe
    let credentialURL: URL?
    let identityURL: URL?
    /// 用户主动停止，进程退出后不得自动重连。
    var manuallyStopped: Bool = false
    /// 认证已成功并稳定运行。仅此类异常断开才允许重连。
    var didConnect: Bool = false
    /// 密码或密钥认证失败，不得自动重连。
    var authFailed: Bool = false

    func cleanup() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        if let url = identityURL {
            url.stopAccessingSecurityScopedResource()
        }
        if let url = credentialURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 进程退出后把管道里剩余输出读完，避免漏掉 Permission denied。
    func drainRemainingOutput() -> String {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        guard let data = try? outputPipe.fileHandleForReading.readToEnd(), !data.isEmpty else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// 隧道进程管理：启动/停止 ssh，并在异常断开且有网络时自动重连。
@MainActor
final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()

    @Published private(set) var statuses: [UUID: TunnelStatus] = [:]
    /// 至少有一条隧道处于占用中时，状态栏图标使用正常亮度。
    @Published private(set) var hasActiveConnection = false

    private var sessions: [UUID: RunningSession] = [:]
    /// 本次运行中的密码（未写入钥匙串时也用于连接与重连）。
    private var sessionPasswords: [UUID: String] = [:]
    /// 本次运行中的私钥口令。
    private var sessionKeyPassphrases: [UUID: String] = [:]
    private var reconnectTasks: [UUID: Task<Void, Never>] = [:]
    /// 启动后需等 ssh 真正认证成功，才视为已连接。
    private var connectConfirmTasks: [UUID: Task<Void, Never>] = [:]
    /// 曾成功连接、异常断开后等待重连的隧道。
    private var reconnectCandidates: [UUID: Tunnel] = [:]
    /// 用户手动停止过的隧道，网络恢复后不得自动拉起。
    private var userStoppedIDs: Set<UUID> = []
    private var networkResumeTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let maxLogLines = 500

    private init() {
        observeNetwork()
    }

    // MARK: - Public API

    func status(for tunnel: Tunnel) -> TunnelStatus {
        statuses[tunnel.id] ?? TunnelStatus(tunnelID: tunnel.id)
    }

    func isRunning(_ tunnel: Tunnel) -> Bool {
        status(for: tunnel).state.isActive
    }

    func toggle(_ tunnel: Tunnel) {
        if isRunning(tunnel) {
            stop(tunnel)
        } else {
            start(tunnel)
        }
    }

    /// 把编辑页中的密码记入内存，即使未保存到钥匙串也能连接。
    func setSessionPassword(_ password: String, for tunnelID: UUID) {
        if password.isEmpty {
            sessionPasswords.removeValue(forKey: tunnelID)
        } else {
            sessionPasswords[tunnelID] = password
        }
    }

    func sessionPassword(for tunnelID: UUID) -> String? {
        sessionPasswords[tunnelID]
    }

    /// 把编辑页中的私钥口令记入内存。
    func setSessionKeyPassphrase(_ passphrase: String, for tunnelID: UUID) {
        if passphrase.isEmpty {
            sessionKeyPassphrases.removeValue(forKey: tunnelID)
        } else {
            sessionKeyPassphrases[tunnelID] = passphrase
        }
    }

    func sessionKeyPassphrase(for tunnelID: UUID) -> String? {
        sessionKeyPassphrases[tunnelID]
    }

    /// 用户手动启动。
    func start(_ tunnel: Tunnel) {
        start(tunnel, isReconnect: false)
    }

    /// - Parameter isReconnect: 自动重连时保留候选队列，避免被当成用户重新启动。
    private func start(_ tunnel: Tunnel, isReconnect: Bool) {
        guard sessions[tunnel.id] == nil else { return }
        cancelReconnect(for: tunnel.id)
        if !isReconnect {
            userStoppedIDs.remove(tunnel.id)
            reconnectCandidates.removeValue(forKey: tunnel.id)
        }

        updateStatus(id: tunnel.id, state: .starting)

        var identityURL: URL?
        var credentialURL: URL?

        do {
            let password = resolvePassword(for: tunnel)
            let keyPassphrase = resolveKeyPassphrase(for: tunnel)

            if tunnel.authMethod == .password {
                guard let password, !password.isEmpty else {
                    throw TunnelLaunchError.missingPassword
                }
            }

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
                outputPipe: pipe,
                credentialURL: credentialURL,
                identityURL: identityURL
            )
            let tunnelID = tunnel.id
            sessions[tunnelID] = session

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
                Task { @MainActor [weak self, tunnelID] in
                    self?.consumeSSHOutput(id: tunnelID, text: text)
                }
            }

            process.terminationHandler = { [weak self] process in
                Task { @MainActor [tunnelID] in
                    self?.handleTermination(tunnelID: tunnelID, exitCode: Int(process.terminationStatus))
                }
            }

            try process.run()
            reconnectCandidates.removeValue(forKey: tunnelID)
            updateStatus(id: tunnelID, state: .starting, pid: process.processIdentifier)
            appendLog(id: tunnelID, text: "[TunX] 启动 ssh (pid: \(process.processIdentifier))\n")
            appendLog(id: tunnelID, text: "[TunX] 命令: ssh \(invocation.arguments.joined(separator: " "))\n")
            scheduleConnectConfirmation(for: tunnelID)
        } catch {
            if let existing = sessions[tunnel.id] {
                existing.cleanup()
                sessions.removeValue(forKey: tunnel.id)
            }
            identityURL?.stopAccessingSecurityScopedResource()
            if let url = credentialURL {
                try? FileManager.default.removeItem(at: url)
            }
            updateStatus(id: tunnel.id, state: .error, lastError: error.localizedDescription)
            appendLog(id: tunnel.id, text: "[TunX] 启动失败: \(error.localizedDescription)\n")
            if isReconnect {
                if error is TunnelLaunchError {
                    abandonReconnect(for: tunnel.id)
                } else {
                    retryReconnectIfNeeded(for: tunnel, reason: error.localizedDescription)
                }
            }
        }
    }

    /// 用户停止：标记为手动停止，进程退出后不会自动重连。
    func stop(_ tunnel: Tunnel) {
        abandonReconnect(for: tunnel.id)
        cancelConnectConfirmation(for: tunnel.id)
        guard let session = sessions[tunnel.id] else {
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

    /// 结束全部隧道与重连任务。退出应用时会同步等待 ssh 退出，避免留下孤儿进程。
    func stopAll() {
        networkResumeTask?.cancel()
        networkResumeTask = nil
        for task in connectConfirmTasks.values {
            task.cancel()
        }
        connectConfirmTasks.removeAll()

        let snapshot = sessions
        let candidateIDs = Array(reconnectCandidates.keys)
        for id in Set(snapshot.keys).union(candidateIDs) {
            abandonReconnect(for: id)
        }

        for (id, session) in snapshot {
            var updated = session
            updated.manuallyStopped = true
            sessions[id] = updated
            session.process.terminationHandler = nil
            session.outputPipe.fileHandleForReading.readabilityHandler = nil
            if session.process.isRunning {
                session.process.terminate()
            }
        }

        let deadline = Date().addingTimeInterval(0.8)
        for (_, session) in snapshot {
            while session.process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if session.process.isRunning {
                kill(session.process.processIdentifier, SIGKILL)
            }
            session.cleanup()
        }

        sessions.removeAll()
        for id in Set(snapshot.keys).union(candidateIDs) {
            updateStatus(id: id, state: .stopped)
        }
    }

    func clearKeychainItems(for tunnel: Tunnel) {
        try? KeychainManager.shared.deletePassword(account: KeychainAccount.password(tunnel.id))
        try? KeychainManager.shared.deletePassword(account: KeychainAccount.keyPassphrase(tunnel.id))
        sessionPasswords.removeValue(forKey: tunnel.id)
        sessionKeyPassphrases.removeValue(forKey: tunnel.id)
    }

    /// 内存中的凭证优先，没有再读钥匙串。
    private func resolvePassword(for tunnel: Tunnel) -> String? {
        guard tunnel.authMethod == .password else { return nil }
        if let session = sessionPasswords[tunnel.id], !session.isEmpty {
            return session
        }
        return KeychainManager.shared.readPassword(account: KeychainAccount.password(tunnel.id))
    }

    private func resolveKeyPassphrase(for tunnel: Tunnel) -> String? {
        guard tunnel.authMethod == .identityFile else { return nil }
        if let session = sessionKeyPassphrases[tunnel.id], !session.isEmpty {
            return session
        }
        return KeychainManager.shared.readPassword(account: KeychainAccount.keyPassphrase(tunnel.id))
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

    /// ssh 进程退出。仅“已认证连接后非手动断开”才会进入重连。
    private func handleTermination(tunnelID: UUID, exitCode: Int) {
        guard let session = sessions[tunnelID] else { return }
        cancelConnectConfirmation(for: tunnelID)

        let leftover = session.drainRemainingOutput()
        if !leftover.isEmpty {
            consumeSSHOutput(id: tunnelID, text: leftover)
        }

        let latest = sessions[tunnelID] ?? session
        latest.cleanup()
        sessions.removeValue(forKey: tunnelID)

        if latest.manuallyStopped || userStoppedIDs.contains(tunnelID) {
            abandonReconnect(for: tunnelID)
            updateStatus(id: tunnelID, state: .stopped)
            appendLog(id: tunnelID, text: "[TunX] 已停止\n")
            return
        }

        let combinedLog = (statuses[tunnelID]?.log ?? "") + leftover
        if latest.authFailed || SSHOutputClassifier.isAuthenticationFailure(combinedLog) {
            abandonReconnect(for: tunnelID)
            let message = "认证失败，请检查密码或密钥"
            updateStatus(id: tunnelID, state: .error, lastError: message)
            appendLog(id: tunnelID, text: "[TunX] \(message)\n")
            return
        }

        let errorMessage = exitCode == 0 ? "连接已断开" : "ssh 退出码 \(exitCode)"
        appendLog(id: tunnelID, text: "[TunX] \(errorMessage)\n")

        // 启动阶段失败（含密码错误）不重连；只有曾经运行中的隧道才自动重连
        let wasConnected = latest.didConnect && statuses[tunnelID]?.state == .running
        let tunnel = latest.tunnel
        guard wasConnected, tunnel.autoReconnect else {
            reconnectCandidates.removeValue(forKey: tunnelID)
            updateStatus(id: tunnelID, state: .error, lastError: errorMessage)
            return
        }

        reconnectCandidates[tunnelID] = tunnel
        retryReconnectIfNeeded(for: tunnel, reason: errorMessage)
    }

    private func consumeSSHOutput(id: UUID, text: String) {
        appendLog(id: id, text: text)
        guard var session = sessions[id], !session.authFailed else { return }
        if SSHOutputClassifier.isAuthenticationFailure(text) {
            session.authFailed = true
            sessions[id] = session
            cancelConnectConfirmation(for: id)
        }
    }

    /// ssh 进程能跑起来不等于已经认证成功，稍等后再标为运行中。
    private func scheduleConnectConfirmation(for tunnelID: UUID) {
        cancelConnectConfirmation(for: tunnelID)
        connectConfirmTasks[tunnelID] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.confirmConnectionIfNeeded(tunnelID)
        }
    }

    private func cancelConnectConfirmation(for tunnelID: UUID) {
        connectConfirmTasks[tunnelID]?.cancel()
        connectConfirmTasks.removeValue(forKey: tunnelID)
    }

    private func confirmConnectionIfNeeded(_ tunnelID: UUID) {
        guard var session = sessions[tunnelID] else { return }
        guard session.process.isRunning, !session.manuallyStopped, !session.authFailed else { return }
        session.didConnect = true
        sessions[tunnelID] = session
        reconnectCandidates.removeValue(forKey: tunnelID)
        updateStatus(id: tunnelID, state: .running, pid: session.process.processIdentifier)
        appendLog(id: tunnelID, text: "[TunX] 连接已建立\n")
    }

    private func observeNetwork() {
        NetworkMonitor.shared.$isSatisfied
            .removeDuplicates()
            .dropFirst() // 忽略订阅时的初始值，只响应后续网络变化
            .sink { [weak self] isSatisfied in
                self?.handleNetworkChange(isSatisfied: isSatisfied)
            }
            .store(in: &cancellables)
    }

    /// 网络恢复后稍作延迟再重连，避免路径抖动时立刻发起 ssh。
    private func handleNetworkChange(isSatisfied: Bool) {
        networkResumeTask?.cancel()
        if isSatisfied {
            networkResumeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.resumeReconnectsIfNeeded()
            }
        } else {
            pauseReconnectsForOffline()
        }
    }

    private func pauseReconnectsForOffline() {
        // 无网络时取消已安排的重连任务，等路径恢复后再试
        let waitingIDs = Set(reconnectTasks.keys).union(reconnectCandidates.keys)
        for task in reconnectTasks.values {
            task.cancel()
        }
        reconnectTasks.removeAll()

        for id in waitingIDs where !userStoppedIDs.contains(id) {
            updateStatus(id: id, state: .reconnecting, lastError: "无网络，等待恢复")
            appendLog(id: id, text: "[TunX] 网络已断开，暂停重连，待网络恢复后再试\n")
        }
    }

    /// 仅重连：用户未手动停止、且仍在候选队列中的隧道。
    private func resumeReconnectsIfNeeded() {
        guard NetworkMonitor.shared.isSatisfied else { return }
        let pending = reconnectCandidates
        for (id, tunnel) in pending {
            guard sessions[id] == nil else { continue }
            guard !userStoppedIDs.contains(id), tunnel.autoReconnect else {
                abandonReconnect(for: id)
                updateStatus(id: id, state: .stopped)
                continue
            }
            appendLog(id: id, text: "[TunX] 网络已恢复，开始重连\n")
            start(tunnel, isReconnect: true)
        }
    }

    private func retryReconnectIfNeeded(for tunnel: Tunnel, reason: String) {
        guard reconnectCandidates[tunnel.id] != nil else { return }
        guard !userStoppedIDs.contains(tunnel.id), tunnel.autoReconnect else {
            abandonReconnect(for: tunnel.id)
            return
        }
        guard NetworkMonitor.shared.isSatisfied else {
            updateStatus(id: tunnel.id, state: .reconnecting, lastError: "无网络，等待恢复")
            appendLog(id: tunnel.id, text: "[TunX] 当前无网络，待网络恢复后再重连\n")
            return
        }
        scheduleReconnect(for: tunnel, reason: reason)
    }

    private func scheduleReconnect(for tunnel: Tunnel, reason: String) {
        let tunnelID = tunnel.id
        let delay = max(1, tunnel.reconnectDelay)
        let nextAttempt = Date().addingTimeInterval(TimeInterval(delay))
        updateStatus(id: tunnelID, state: .reconnecting, lastError: reason, nextReconnect: nextAttempt)
        appendLog(id: tunnelID, text: "[TunX] 将在 \(delay) 秒后自动重连…\n")

        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay) * NSEC_PER_SEC)
            guard let self, !Task.isCancelled else { return }
            guard self.sessions[tunnelID] == nil else { return }
            guard !self.userStoppedIDs.contains(tunnelID) else { return }
            guard NetworkMonitor.shared.isSatisfied else {
                self.updateStatus(id: tunnelID, state: .reconnecting, lastError: "无网络，等待恢复")
                self.appendLog(id: tunnelID, text: "[TunX] 当前无网络，待网络恢复后再重连\n")
                return
            }
            self.start(tunnel, isReconnect: true)
        }
        reconnectTasks[tunnelID] = task
    }

    /// 取消定时重连并记录用户停止意图。
    private func abandonReconnect(for tunnelID: UUID) {
        userStoppedIDs.insert(tunnelID)
        reconnectCandidates.removeValue(forKey: tunnelID)
        cancelReconnect(for: tunnelID)
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

        switch state {
        case .stopped, .stopping:
            // 用户停止或结束重连后，不再保留失败原因与下次重连时间
            status.lastError = nil
            status.nextReconnect = nil
            status.pid = nil
        case .running:
            status.lastError = nil
            status.nextReconnect = nil
            if let pid { status.pid = pid }
        case .starting:
            status.nextReconnect = nil
            status.lastError = lastError
            if let pid { status.pid = pid }
        case .reconnecting:
            status.pid = nil
            if let lastError { status.lastError = lastError }
            status.nextReconnect = nextReconnect
        case .error:
            status.pid = nil
            status.nextReconnect = nil
            if let lastError { status.lastError = lastError }
        }

        statuses[id] = status
        refreshActiveConnection()
    }

    /// 刷新状态栏图标亮度：有任意占用中的隧道则为正常颜色。
    private func refreshActiveConnection() {
        let active = statuses.values.contains { $0.state.isActive }
        if hasActiveConnection != active {
            hasActiveConnection = active
        }
    }

    private func appendLog(id: UUID, text: String) {
        var status = statuses[id] ?? TunnelStatus(tunnelID: id)
        status.log.append(text)
        var lines = status.log.components(separatedBy: "\n")
        // 限制日志行数，避免长时间运行占用过多内存
        if lines.count > maxLogLines {
            lines = Array(lines.suffix(maxLogLines))
            status.log = lines.joined(separator: "\n")
        }
        statuses[id] = status
    }
}

/// 从 OpenSSH 输出判断是否为不可重试的认证失败。
private enum SSHOutputClassifier {
    static func isAuthenticationFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "permission denied",
            "authentication failed",
            "too many authentication failures",
            "incorrect passphrase",
            "wrong passphrase",
            "bad passphrase"
        ]
        return markers.contains { lower.contains($0) }
    }
}
