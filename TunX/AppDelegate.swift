//
//  AppDelegate.swift
//  TunX
//
//  Created by glli on 2026/8/16.
//

import SwiftUI
import AppKit
import SwiftData
import Combine

/// 菜单栏常驻应用代理：状态栏图标、系统菜单与主窗口。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var mainWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()

    lazy var modelContainer: ModelContainer = {
        let schema = Schema([
            Tunnel.self,
            ForwardRule.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动时隐藏 Dock，仅保留状态栏图标
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupMainWindow()
        observeNotifications()
        observeTunnelStatus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Setup

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = makeStatusBarIcon()
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.toolTip = "TunX"

        let menu = NSMenu()
        menu.delegate = self
        // 直接绑定菜单后，左键与右键都会弹出系统标准菜单
        item.menu = menu

        statusItem = item
        updateStatusBarAppearance(active: TunnelManager.shared.hasActiveConnection)
    }

    /// 自定义 Tx 图标作为 template，以适配浅色/深色菜单栏。
    private func makeStatusBarIcon() -> NSImage? {
        guard let original = NSImage(named: "StatusBarIcon") else {
            return NSImage(systemSymbolName: "network", accessibilityDescription: "TunX")
        }
        let image = original.copy() as? NSImage ?? original
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private func setupMainWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TunX"
        window.identifier = NSUserInterfaceItemIdentifier("main")
        window.minSize = NSSize(width: 800, height: 500)
        window.contentViewController = NSHostingController(
            rootView: ContentView().modelContainer(modelContainer)
        )
        window.center()
        mainWindowController = NSWindowController(window: window)
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openMainWindow),
            name: .openTunXMainWindow,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: mainWindowController?.window
        )
    }

    private func observeTunnelStatus() {
        TunnelManager.shared.$hasActiveConnection
            .sink { [weak self] active in
                self?.updateStatusBarAppearance(active: active)
            }
            .store(in: &cancellables)
    }

    /// 全部断开时略微降低透明度，有连接时恢复原色。
    private func updateStatusBarAppearance(active: Bool) {
        guard let button = statusItem?.button else { return }
        button.alphaValue = active ? 1.0 : 0.78
    }

    // MARK: - Status Menu

    /// 每次弹出状态栏菜单时重建，以反映最新隧道与连接状态。
    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let tunnels = fetchTunnels()
        let manager = TunnelManager.shared

        if tunnels.isEmpty {
            let emptyItem = NSMenuItem(title: "暂无隧道", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for tunnel in tunnels {
                let status = manager.status(for: tunnel)
                let item = NSMenuItem(
                    title: "\(tunnel.displayName)  —  \(status.state.label)",
                    action: #selector(toggleTunnel(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = tunnel.id
                item.state = menuState(for: status.state)
                item.image = statusDotImage(for: status.state)
                item.toolTip = tooltip(for: tunnel, status: status)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "打开 TunX", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApplication), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func fetchTunnels() -> [Tunnel] {
        let descriptor = FetchDescriptor<Tunnel>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? modelContainer.mainContext.fetch(descriptor)) ?? []
    }

    private func menuState(for state: TunnelState) -> NSControl.StateValue {
        switch state {
        case .running:
            return .on
        case .starting, .stopping, .reconnecting:
            return .mixed
        case .stopped, .error:
            return .off
        }
    }

    private func statusDotImage(for state: TunnelState) -> NSImage {
        let color: NSColor
        switch state {
        case .stopped:
            color = .secondaryLabelColor
        case .starting, .stopping, .reconnecting:
            color = .systemOrange
        case .running:
            color = .systemGreen
        case .error:
            color = .systemRed
        }

        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func tooltip(for tunnel: Tunnel, status: TunnelStatus) -> String {
        if status.state == .error, let lastError = status.lastError, !lastError.isEmpty {
            return lastError
        }
        return TunnelManager.shared.isRunning(tunnel) ? "点击断开" : "点击连接"
    }

    // MARK: - Actions

    @objc private func toggleTunnel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        let targetID = id
        let descriptor = FetchDescriptor<Tunnel>(
            predicate: #Predicate { $0.id == targetID }
        )
        guard let tunnel = try? modelContainer.mainContext.fetch(descriptor).first else { return }
        TunnelManager.shared.toggle(tunnel)
    }

    /// 打开主窗口时临时显示 Dock，便于 Cmd-Tab 切换。
    @objc private func openMainWindow() {
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    /// 关闭主窗口后重新隐藏 Dock，应用继续在状态栏运行。
    @objc private func mainWindowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// 每次打开状态栏菜单前刷新隧道列表与连接状态。
extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildStatusMenu(menu)
    }
}

extension Notification.Name {
    static let openTunXMainWindow = Notification.Name("openTunXMainWindow")
}
