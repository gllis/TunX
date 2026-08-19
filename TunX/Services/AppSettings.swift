//
//  AppSettings.swift
//  TunX
//
//  Created by glli on 2026/8/18.
//

import Foundation
import Combine
import ServiceManagement

/// UserDefaults 键与 SSH 保活取值范围，供设置页与命令构建共用。
nonisolated enum AppSettingsStorage {
    static let showLogs = "showLogs"
    static let serverAliveInterval = "serverAliveInterval"
    static let serverAliveCountMax = "serverAliveCountMax"

    static let defaultServerAliveInterval = 60
    static let defaultServerAliveCountMax = 3
    static let serverAliveIntervalRange = 0...3_600
    static let serverAliveCountMaxRange = 1...30
}

/// 应用级设置：显示日志、开机自启、SSH 保活。
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultServerAliveInterval = AppSettingsStorage.defaultServerAliveInterval
    static let defaultServerAliveCountMax = AppSettingsStorage.defaultServerAliveCountMax
    static let serverAliveIntervalRange = AppSettingsStorage.serverAliveIntervalRange
    static let serverAliveCountMaxRange = AppSettingsStorage.serverAliveCountMaxRange

    /// 是否在隧道详情中显示 ssh 日志，默认关闭。
    @Published var showLogs: Bool {
        didSet {
            UserDefaults.standard.set(showLogs, forKey: AppSettingsStorage.showLogs)
        }
    }

    /// OpenSSH `ServerAliveInterval`（秒）。0 表示关闭心跳。
    @Published var serverAliveInterval: Int {
        didSet {
            let clamped = Self.clamp(serverAliveInterval, to: Self.serverAliveIntervalRange)
            if clamped != serverAliveInterval {
                serverAliveInterval = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: AppSettingsStorage.serverAliveInterval)
        }
    }

    /// OpenSSH `ServerAliveCountMax`，连续无响应次数上限。
    @Published var serverAliveCountMax: Int {
        didSet {
            let clamped = Self.clamp(serverAliveCountMax, to: Self.serverAliveCountMaxRange)
            if clamped != serverAliveCountMax {
                serverAliveCountMax = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: AppSettingsStorage.serverAliveCountMax)
        }
    }

    /// 是否在登录时启动，以系统登录项状态为准。
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var launchAtLoginMessage: String?

    private init() {
        showLogs = UserDefaults.standard.bool(forKey: AppSettingsStorage.showLogs)
        serverAliveInterval = Self.sshServerAliveInterval
        serverAliveCountMax = Self.sshServerAliveCountMax
        launchAtLogin = Self.loginItemEnabled
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = Self.loginItemEnabled
        if SMAppService.mainApp.status == .requiresApproval {
            launchAtLoginMessage = "请在系统设置 › 通用 › 登录项中允许 TunX"
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = Self.loginItemEnabled
            launchAtLoginMessage = nil
            if SMAppService.mainApp.status == .requiresApproval {
                launchAtLoginMessage = "请在系统设置 › 通用 › 登录项中允许 TunX"
            }
        } catch {
            launchAtLogin = Self.loginItemEnabled
            launchAtLoginMessage = error.localizedDescription
        }
    }

    /// 供非 UI 代码读取当前保活间隔，不依赖主线程隔离。
    nonisolated static var sshServerAliveInterval: Int {
        storedInt(
            for: AppSettingsStorage.serverAliveInterval,
            default: AppSettingsStorage.defaultServerAliveInterval,
            range: AppSettingsStorage.serverAliveIntervalRange
        )
    }

    /// 供非 UI 代码读取当前保活次数上限，不依赖主线程隔离。
    nonisolated static var sshServerAliveCountMax: Int {
        storedInt(
            for: AppSettingsStorage.serverAliveCountMax,
            default: AppSettingsStorage.defaultServerAliveCountMax,
            range: AppSettingsStorage.serverAliveCountMaxRange
        )
    }

    private static var loginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    nonisolated private static func storedInt(
        for key: String,
        default defaultValue: Int,
        range: ClosedRange<Int>
    ) -> Int {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return clamp(defaults.integer(forKey: key), to: range)
    }

    nonisolated private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
