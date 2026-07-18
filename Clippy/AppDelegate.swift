//
//  AppDelegate.swift
//  Clippy
//
//  Sets up the status item + popover and coordinates capture and pasting.
//

import AppKit
import SwiftUI

/// Owns the menu bar status item, the popover, the store, and the clipboard monitor.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let store = ClipboardStore()
    private lazy var monitor = ClipboardMonitor(store: store)

    /// The last app (other than Clippy) that was frontmost — the paste target.
    ///
    /// Tracked continuously via a workspace notification rather than captured when the
    /// popover opens: clicking the status item activates Clippy, so by the time the
    /// popover opens the "frontmost" app is already us, and the real target is lost.
    private var previousApp: NSRunningApplication?

    /// Monitors clicks outside Clippy so the popover can dismiss itself like a native one,
    /// without the status-item double-toggle that `.transient` behavior would cause.
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a menu bar agent: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
        observeActiveApp()
        monitor.start()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Clippy") {
                image.isTemplate = true
                button.image = image
            } else {
                // Fallback so the item is always visible even if the symbol is unavailable.
                button.title = "📎"
            }
            button.action = #selector(togglePopover)
            button.target = self
        }
        statusItem = item
    }

    private func setupPopover() {
        // Application-defined (not `.transient`) so the status-item click reliably toggles
        // open/close. Click-away dismissal is handled by `outsideClickMonitor` instead,
        // which avoids the double-fire where a transient popover closes on the same click
        // that then re-triggers the button action and reopens it.
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentSize = NSSize(width: 340, height: 460)

        let content = PopoverContentView(store: store) { [weak self] item in
            self?.paste(item)
        }
        popover.contentViewController = NSHostingController(rootView: content)
    }

    /// Continuously remembers the last non-Clippy app to become frontmost, so we always
    /// know where to paste even after Clippy itself steals focus.
    private func observeActiveApp() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func activeAppChanged(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        if app.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = app
        }
    }

    // MARK: - Popover

    /// Toggles the popover: opens it if closed, closes it if open.
    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Bring the popover forward and make it key so it's interactive immediately.
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()

        // Start watching for clicks outside Clippy so we can dismiss like a native popover.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - Paste

    /// Places the item back on the pasteboard and pastes it into the previous app.
    private func paste(_ item: ClipboardItem) {
        // Check permissions FIRST before modifying the pasteboard.
        guard AccessibilityPermission.isTrusted else {
            // First paste attempt without permission: prompt and point to Settings.
            AccessibilityPermission.request()
            AccessibilityPermission.openSettings()
            return
        }

        // Make the selection the current clipboard content so a paste (manual or
        // synthesized) inserts it. Suppress so the monitor ignores our own write.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        monitor.suppressCurrentChange()

        // Close the popover and hand focus back to the target app, then paste into it.
        closePopover()

        guard let targetApp = previousApp else { return }
        targetApp.activate()

        Task {
            // Give the target app time to become frontmost and focus a text field.
            try? await Task.sleep(for: .milliseconds(180))
            Paster.simulateCommandV()
        }
    }
}
