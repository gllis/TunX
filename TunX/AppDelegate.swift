//
//  AppDelegate.swift
//  TunX
//
//  Created by liguilong on 2026/8/16.
//

import SwiftUI
import AppKit
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var contextMenu: NSMenu?
    private var mainWindowController: NSWindowController?

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
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
        setupContextMenu()
        setupMainWindow()
        observeNotifications()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Setup

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "network", accessibilityDescription: "TunX")
        item.button?.target = self
        item.button?.action = #selector(statusBarButtonClicked(_:))
        item.button?.sendAction(on: NSEvent.EventTypeMask([.leftMouseUp, .rightMouseUp]))
        statusItem = item
    }

    private func setupPopover() {
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 240, height: 320)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView().modelContainer(modelContainer)
        )
        self.popover = popover
    }

    private func setupContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开 TunX", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApplication), keyEquivalent: "q"))
        self.contextMenu = menu
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

    // MARK: - Actions

    @objc private func statusBarButtonClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        guard let statusItem = statusItem, let contextMenu = contextMenu else { return }
        statusItem.menu = contextMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openMainWindow() {
        closePopover()
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApplication() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func mainWindowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
    }
}

extension Notification.Name {
    static let openTunXMainWindow = Notification.Name("openTunXMainWindow")
}
