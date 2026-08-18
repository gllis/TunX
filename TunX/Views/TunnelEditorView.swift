//
//  TunnelEditorView.swift
//  TunX
//
//  Created by glli on 2026/8/13.
//

import SwiftUI
import SwiftData

/// 隧道详情编辑页：基本信息、认证、转发规则、高级选项与日志。
struct TunnelEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var tunnel: Tunnel

    @StateObject private var manager = TunnelManager.shared

    @State private var password: String = ""
    @State private var savePassword: Bool = false
    @State private var keyPassphrase: String = ""
    @State private var saveKeyPassphrase: Bool = false

    var body: some View {
        let status = manager.status(for: tunnel)

        Form {
            Section("基本信息") {
                TextField("名称", text: $tunnel.name)
                TextField("主机", text: $tunnel.host)
                HStack {
                    TextField("端口", text: intBinding(for: \.port))
                        .frame(width: 80)
                    TextField("用户名", text: $tunnel.user)
                }
            }

            Section("认证方式") {
                Picker("认证", selection: authMethodBinding) {
                    ForEach(AuthMethod.allCases) { method in
                        Text(method.label).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if tunnel.authMethod == .password {
                    SecureField("密码", text: $password)
                    Toggle("保存到钥匙串", isOn: $savePassword)
                } else {
                    HStack {
                        TextField("私钥路径", text: identityFileBinding)
                        Button("选择…") { chooseIdentityFile() }
                    }
                    SecureField("私钥口令（如已加密）", text: $keyPassphrase)
                    Toggle("保存口令到钥匙串", isOn: $saveKeyPassphrase)
                }
            }

            Section("转发规则") {
                ForEach($tunnel.rules) { $rule in
                    ForwardRuleEditor(rule: $rule) {
                        deleteRule($rule.wrappedValue)
                    }
                }

                Button("添加规则") {
                    let rule = ForwardRule(
                        type: .local,
                        localHost: "127.0.0.1",
                        localPort: 8080,
                        remoteHost: "localhost",
                        remotePort: 80
                    )
                    tunnel.rules.append(rule)
                }
            }

            Section("高级选项") {
                TextField("额外 SSH 选项（空格分隔）", text: $tunnel.extraOptions)
                Toggle("自动重连", isOn: $tunnel.autoReconnect)
                if tunnel.autoReconnect {
                    Stepper("重连间隔：\(tunnel.reconnectDelay) 秒", value: $tunnel.reconnectDelay, in: 1...300)
                }
            }

            Section("状态与日志") {
                HStack(alignment: .top, spacing: 12) {
                    StatusBadge(state: status.state)

                    VStack(alignment: .leading, spacing: 4) {
                        if let pid = status.pid {
                            Text("进程 PID: \(pid)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let error = status.lastError {
                            Text("错误: \(error)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if let next = status.nextReconnect {
                            Text("下次重连: \(next, format: .dateTime)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button(manager.isRunning(tunnel) ? "停止" : "启动") {
                        manager.toggle(tunnel)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(manager.isRunning(tunnel) ? .red : .green)
                }

                HStack {
                    Text("OpenSSH 命令")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("复制") {
                        copyCommand()
                    }
                    .font(.caption)
                }

                Text(manager.generatedCommand(for: tunnel))
                    .font(.caption.monospaced())
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                LogView(log: status.log)
                    .frame(minHeight: 120)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            loadPersistedValues()
        }
        .onChange(of: savePassword) { _, newValue in
            persistPassword(save: newValue)
        }
        .onChange(of: password) { _, _ in
            if savePassword { persistPassword(save: true) }
        }
        .onChange(of: saveKeyPassphrase) { _, newValue in
            persistKeyPassphrase(save: newValue)
        }
        .onChange(of: keyPassphrase) { _, _ in
            if saveKeyPassphrase { persistKeyPassphrase(save: true) }
        }
    }

    // MARK: - Bindings

    private var authMethodBinding: Binding<AuthMethod> {
        Binding(
            get: { tunnel.authMethod },
            set: { tunnel.authMethod = $0 }
        )
    }

    private var identityFileBinding: Binding<String> {
        Binding(
            get: { tunnel.identityFilePath ?? "" },
            set: { tunnel.identityFilePath = $0.nilIfEmpty }
        )
    }

    /// 将 Int 字段绑定到 TextField；非法输入会被忽略。
    private func intBinding(for keyPath: ReferenceWritableKeyPath<Tunnel, Int>) -> Binding<String> {
        Binding(
            get: { String(tunnel[keyPath: keyPath]) },
            set: { newValue in
                if let value = Int(newValue) {
                    tunnel[keyPath: keyPath] = value
                }
            }
        )
    }

    // MARK: - Keychain

    /// 从钥匙串与书签恢复密码、口令及私钥路径。
    private func loadPersistedValues() {
        password = KeychainManager.shared.readPassword(account: KeychainAccount.password(tunnel.id)) ?? ""
        savePassword = !password.isEmpty

        keyPassphrase = KeychainManager.shared.readPassword(account: KeychainAccount.keyPassphrase(tunnel.id)) ?? ""
        saveKeyPassphrase = !keyPassphrase.isEmpty

        loadIdentityBookmark()
    }

    private func loadIdentityBookmark() {
        guard let data = tunnel.identityBookmarkData else { return }
        do {
            let url = try SecurityScopedBookmark.resolve(data)
            tunnel.identityFilePath = url.path
        } catch {
            print("私钥书签已失效: \(error)")
            tunnel.identityBookmarkData = nil
        }
    }

    private func persistPassword(save: Bool) {
        do {
            if save {
                try KeychainManager.shared.savePassword(password, account: KeychainAccount.password(tunnel.id), label: "TunX 密码 – \(tunnel.displayName)")
            } else {
                try KeychainManager.shared.deletePassword(account: KeychainAccount.password(tunnel.id))
            }
        } catch {
            print("钥匙串密码保存失败: \(error)")
        }
    }

    private func persistKeyPassphrase(save: Bool) {
        do {
            if save {
                try KeychainManager.shared.savePassword(keyPassphrase, account: KeychainAccount.keyPassphrase(tunnel.id), label: "TunX 私钥口令 – \(tunnel.displayName)")
            } else {
                try KeychainManager.shared.deletePassword(account: KeychainAccount.keyPassphrase(tunnel.id))
            }
        } catch {
            print("钥匙串口令保存失败: \(error)")
        }
    }

    // MARK: - Actions

    /// 从关系中移除并删除 SwiftData 对象。
    private func deleteRule(_ rule: ForwardRule) {
        tunnel.rules.removeAll { $0.id == rule.id }
        modelContext.delete(rule)
    }

    /// 通过系统文件面板选择私钥，并保存安全作用域书签。
    private func chooseIdentityFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { result in
            if result == .OK, let url = panel.url {
                do {
                    let data = try SecurityScopedBookmark.create(for: url)
                    tunnel.identityBookmarkData = data
                    tunnel.identityFilePath = url.path
                } catch {
                    print("创建私钥书签失败: \(error)")
                    tunnel.identityFilePath = url.path
                }
            }
        }
    }

    private func copyCommand() {
        let command = manager.generatedCommand(for: tunnel)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}

// MARK: - Status Badge

/// 连接状态胶囊标签。
private struct StatusBadge: View {
    let state: TunnelState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.color)
                .frame(width: 8, height: 8)
            Text(state.label)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(state.color.opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - Forward Rule Editor

/// 单条转发规则编辑器，右侧垃圾桶可删除该规则。
private struct ForwardRuleEditor: View {
    @Binding var rule: ForwardRule
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Picker("类型", selection: Binding(
                    get: { rule.type },
                    set: { rule.type = $0 }
                )) {
                    ForEach(ForwardType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("删除规则")
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("本地绑定")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("地址", text: $rule.localHost)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("本地端口")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("端口", text: intBinding(for: \.localPort))
                        .frame(width: 70)
                }

                if rule.type != .dynamic {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("远程主机")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("主机", text: $rule.remoteHost)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("远程端口")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("端口", text: intBinding(for: \.remotePort))
                            .frame(width: 70)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func intBinding(for keyPath: ReferenceWritableKeyPath<ForwardRule, Int>) -> Binding<String> {
        Binding(
            get: { String(rule[keyPath: keyPath]) },
            set: { newValue in
                if let value = Int(newValue) {
                    rule[keyPath: keyPath] = value
                }
            }
        )
    }
}

// MARK: - Log View

/// ssh 输出日志滚动区域。
private struct LogView: View {
    let log: String

    var body: some View {
        ScrollView {
            Text(log)
                .font(.caption.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
