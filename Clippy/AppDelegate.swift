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

    /// The app that was frontmost when the popover opened — the paste target.
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a menu bar agent: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
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
        // Application-defined so the popover only closes when the user dismisses it
        // (via the menu bar icon), never automatically after a paste or a click away.
        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: 320, height: 400)

        let content = PopoverContentView(store: store) { [weak self] item in
            self?.paste(item)
        }
        popover.contentViewController = NSHostingController(rootView: content)
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Remember the app to paste into BEFORE we show the popover and steal focus.
            // Filter out our own app in case we're somehow frontmost.
            let currentFrontmost = NSWorkspace.shared.frontmostApplication
            if currentFrontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousApp = currentFrontmost
            }
            
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Paste

    /// Places the item back on the pasteboard and pastes it into the previous app.
    ///
    /// The popover is left open — the user dismisses it themselves via the menu bar icon.
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

        // Return focus to the app that was frontmost before the popover opened, then
        // paste into it. The popover stays open for further picks.
        guard let targetApp = previousApp else { return }
        
        targetApp.activate(options: [.activateIgnoringOtherApps])

        Task {
            // Give the app time to activate and focus a text field
            try? await Task.sleep(for: .milliseconds(200))
            Paster.simulateCommandV()
        }
    }
}
