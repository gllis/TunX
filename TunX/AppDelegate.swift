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
    private var settingsWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var toolbarObservers: [NSObjectProtocol] = []

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
        setupSettingsWindow()
        observeNotifications()
        observeTunnelStatus()
        DispatchQueue.main.async { [weak self] in
            self?.removeUnwantedMainMenus()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        TunnelManager.shared.stopAll()
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
        window.toolbarStyle = .unified
        window.center()
        mainWindowController = NSWindowController(window: window)
        attachToolbarConfiguration(to: window)
    }

    /// 固定工具栏为仅图标、去掉侧边栏跟踪竖线，并禁用右键切换显示模式。
    private func attachToolbarConfiguration(to window: NSWindow) {
        configureMainWindowToolbar(window)

        if toolbarObservers.isEmpty {
            let becomeKey = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.configureMainWindowToolbar(window)
            }
            let willAddItem = NotificationCenter.default.addObserver(
                forName: NSToolbar.willAddItemNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard notification.object as? NSToolbar === window.toolbar else { return }
                DispatchQueue.main.async {
                    self?.configureMainWindowToolbar(window)
                }
            }
            toolbarObservers = [becomeKey, willAddItem]
        }

        for delay in [0.05, 0.2, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
                guard let window else { return }
                self?.configureMainWindowToolbar(window)
            }
        }
    }

    private func configureMainWindowToolbar(_ window: NSWindow) {
        window.toolbarStyle = .unified
        guard let toolbar = window.toolbar else { return }

        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        if #available(macOS 15.0, *) {
            toolbar.allowsDisplayModeCustomization = false
        }

        // 隐藏跟踪分隔线，但不移除 item，以免破坏原生侧边栏布局
        for item in toolbar.items where item is NSTrackingSeparatorToolbarItem
            || item.itemIdentifier == .sidebarTrackingSeparator
            || item.itemIdentifier.rawValue.lowercased().contains("trackingseparator") {
            item.view?.isHidden = true
            item.view?.alphaValue = 0
            if #available(macOS 15.0, *) {
                item.isHidden = true
            }
        }

        hideToolbarSeparatorViews(in: window)
        disableToolbarDisplayModeMenu(in: window)
    }

    private func hideToolbarSeparatorViews(in window: NSWindow) {
        func walk(_ view: NSView) {
            let name = String(describing: type(of: view))
            let isHairline = view.bounds.width > 0 && view.bounds.width <= 3 && view.bounds.height >= 16
            if name.contains("TrackingSeparator")
                || name.contains("NSToolbarSeparator")
                || (name.contains("Toolbar") && name.contains("Separator"))
                || (isHairline && name.contains("Separator")) {
                view.isHidden = true
                view.alphaValue = 0
            }
            view.subviews.forEach(walk)
        }

        if let themeFrame = window.contentView?.superview {
            walk(themeFrame)
        }
        if let titlebar = window.standardWindowButton(.closeButton)?.superview?.superview {
            walk(titlebar)
        }
    }

    private func disableToolbarDisplayModeMenu(in window: NSWindow) {
        let emptyMenu = NSMenu()
        emptyMenu.autoenablesItems = false

        func walk(_ view: NSView) {
            let name = String(describing: type(of: view))
            if name.contains("Toolbar") {
                view.menu = emptyMenu
            }
            view.subviews.forEach(walk)
        }

        if let themeFrame = window.contentView?.superview {
            walk(themeFrame)
        }
        if let titlebar = window.standardWindowButton(.closeButton)?.superview?.superview {
            walk(titlebar)
        }
    }

    /// 独立设置窗口。状态栏菜单无法可靠触发 SwiftUI Settings Scene，因此自行托管。
    private func setupSettingsWindow() {
        let hosting = NSHostingController(rootView: SettingsView())
        hosting.sizingOptions = [.intrinsicContentSize]

        let window = NSWindow(contentViewController: hosting)
        window.title = "设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.setContentSize(hosting.view.fittingSize)
        window.center()
        settingsWindowController = NSWindowController(window: window)
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
            selector: #selector(openSettings),
            name: .openTunXSettings,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(removeUnwantedMainMenus),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    /// 去掉系统默认的 Edit / View 菜单。
    @objc private func removeUnwantedMainMenus() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let itemsToRemove = mainMenu.items.filter { isEditMenu($0) || isViewMenu($0) }
        for item in itemsToRemove {
            mainMenu.removeItem(item)
        }
    }

    private func isEditMenu(_ item: NSMenuItem) -> Bool {
        let title = item.title
        if title == "Edit" || title == "编辑" {
            return true
        }
        return item.submenu?.items.contains { $0.action == Selector(("undo:")) } == true
    }

    private func isViewMenu(_ item: NSMenuItem) -> Bool {
        ["View", "显示", "视图"].contains(item.title)
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
                    title: "\(tunnel.displayName)",
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

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

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
        if let window = mainWindowController?.window {
            attachToolbarConfiguration(to: window)
        }
    }

    @objc private func openSettings() {
        // 等状态栏菜单关闭后再弹出，否则窗口可能被菜单跟踪吞掉
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            guard let window = self.settingsWindowController?.window else { return }
            if let hosting = window.contentViewController {
                hosting.view.layoutSubtreeIfNeeded()
                var size = hosting.view.fittingSize
                if size.width < 520 { size.width = 520 }
                if size.height < 400 { size.height = 400 }
                window.setContentSize(size)
            }
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    /// 最后一个窗口关闭后重新隐藏 Dock，应用继续在状态栏运行。
    @objc private func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard self != nil else { return }
            let closing = notification.object as? NSWindow
            let hasVisibleWindow = NSApp.windows.contains { window in
                window !== closing
                    && window.isVisible
                    && window.styleMask.contains(.titled)
            }
            if !hasVisibleWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
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
    static let openTunXSettings = Notification.Name("openTunXSettings")
}
