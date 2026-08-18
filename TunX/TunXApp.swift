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
        // 保留空 Settings，避免 SwiftUI App 因缺少 Scene 无法启动
        Settings {
            EmptyView()
        }
    }
}
