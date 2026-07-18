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
        // Application-defined so the popover never auto-closes: it stays open across pastes
        // and dismisses only when the user clicks the menu bar icon again. Clicking away
        // (e.g. into your document to place the cursor) deliberately does not close it.
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
        // Normal (activating) popover: when a paste later activates the target app, Clippy
        // goes inactive and gives up its key window, so the synthesized ⌘V is delivered to
        // that app rather than back into Clippy.
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    // MARK: - Paste

    /// Places the item back on the pasteboard and pastes it into the previous app.
    ///
    /// The popover is left open so several items can be pasted in a row; it closes only via
    /// the status-item toggle.
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

        // Hand focus back to the target app and paste there, leaving the popover open.
        guard let targetApp = previousApp else { return }

        Task {
            // Clicking a row can momentarily re-activate Clippy, racing our own attempt to
            // hand focus back. Keep nudging the target frontmost, and fire ⌘V only once it
            // is confirmed frontmost after a settle AND again right before the keystroke, so
            // the paste can't land in Clippy or error-beep. Give up quietly if focus never
            // stabilizes. Up to ~1.4s of attempts.
            for _ in 0..<40 {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier else {
                    targetApp.activate()
                    try? await Task.sleep(for: .milliseconds(35))
                    continue
                }

                // Target is frontmost: let its focused field settle, then re-verify.
                try? await Task.sleep(for: .milliseconds(50))
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier {
                    Paster.simulateCommandV()
                    return
                }
            }
        }
    }
}
