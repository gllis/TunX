//
//  TunXApp.swift
//  TunX
//
//  Created by glli on 2026/8/13.
//

import SwiftUI

/// 应用入口。实际生命周期由 `AppDelegate` 管理（菜单栏常驻、无独立窗口 Scene）。
@main
struct TunXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    NotificationCenter.default.post(name: .openTunXSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .pasteboard) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
        }
    }
}
