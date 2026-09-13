//
//  AppDelegate.swift
//  Clippy
//
//  Sets up the status item + floating panel and coordinates capture and pasting.
//

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

/// A panel that can never become the key or main window.
///
/// This is the crux of reliable pasting: because showing it never takes keyboard focus,
/// the app the user is pasting into stays frontmost and key the entire time, so a
/// synthesized ⌘V is delivered there instead of back to Clippy. It still receives mouse
/// clicks (it's a non-activating panel), so rows remain tappable.
final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

extension Notification.Name {
    /// Posted each time the panel is ordered front, so SwiftUI content can refresh
    /// state that may have changed while it was hidden (e.g. the login item toggle).
    static let clippyPanelDidOpen = Notification.Name("ClippyPanelDidOpen")
}

/// Owns the menu bar status item, the panel, the store, and the clipboard monitor.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private var panel: ClipboardPanel?
    private let store = ClipboardStore()
    private lazy var monitor = ClipboardMonitor(store: store)

    /// The last app (other than Clippy) that was frontmost — the paste target.
    private var previousApp: NSRunningApplication?

    /// Escape-to-close hot key, registered only while the panel is visible.
    private var escapeHotKeyID: UInt32?

    /// Consumes numeric selection while the panel is presented from a text input.
    private lazy var numberKeyInterceptor = NumberKeyInterceptor { [weak self] digit in
        self?.selectNumberedItem(with: digit)
    }
    private var pendingNumberSelection = ""
    private var pendingNumberSelectionTask: Task<Void, Never>?

    /// Whether we've already shown the Accessibility prompt this session, so a
    /// permission-less click doesn't reopen System Settings on every paste attempt.
    private var didPromptForAccessibility = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a menu bar agent: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        // Seed the paste target with whatever was frontmost at launch, so pasting
        // works even before the first app switch is observed.
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }

        setupStatusItem()
        setupPanel()
        setupHotKey()
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
            button.action = #selector(togglePanel)
            button.target = self
        }
        statusItem = item
    }

    private func setupPanel() {
        let panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 460),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = makePanelContent(showsNumberHints: false)

        self.panel = panel
    }

    /// ⌥⌘V from anywhere toggles the panel, so the user never has to reach for the
    /// menu bar mid-typing. (Note: this shadows Finder's "Move Item Here" while
    /// Clippy runs; change the combination here if that bites.)
    private func setupHotKey() {
        HotKeyCenter.shared.register(
            keyCode: kVK_ANSI_V,
            carbonModifiers: cmdKey | optionKey
        ) { [weak self] in
            self?.togglePanel()
        }
    }

    /// Continuously remembers the last non-Clippy app to become frontmost, so we always
    /// know where to paste.
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

    // MARK: - Panel

    /// Toggles the panel: opens it if hidden, closes it if shown. It closes only via
    /// this toggle (status item / ⌥⌘V) or Escape — clicking elsewhere (e.g. into your
    /// document) deliberately leaves it open for multi-paste.
    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        guard let panel,
              let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        let size = panel.frame.size
        let focusedFieldFrame = focusedTextInputFrame()
        let canSelectByNumber = focusedFieldFrame != nil && numberKeyInterceptor.start()
        let origin = panelOrigin(
            for: focusedFieldFrame,
            size: size,
            button: button,
            buttonWindow: buttonWindow
        )
        panel.setFrameOrigin(origin)
        panel.contentView = makePanelContent(showsNumberHints: canSelectByNumber)

        // Order front WITHOUT activating Clippy or making the panel key, so the target app
        // keeps keyboard focus.
        panel.orderFrontRegardless()
        NotificationCenter.default.post(name: .clippyPanelDidOpen, object: nil)

        // The panel never becomes key, so it can't receive keyDown events directly.
        // A transient Escape hot key stands in: while the panel is open, Escape closes
        // it (and is consumed system-wide); it's unregistered the moment the panel closes.
        if escapeHotKeyID == nil {
            escapeHotKeyID = HotKeyCenter.shared.register(
                keyCode: kVK_Escape,
                carbonModifiers: 0
            ) { [weak self] in
                self?.closePanel()
            }
        }
    }

    private func closePanel() {
        panel?.orderOut(nil)
        if let id = escapeHotKeyID {
            HotKeyCenter.shared.unregister(id)
            escapeHotKeyID = nil
        }
        numberKeyInterceptor.stop()
        pendingNumberSelectionTask?.cancel()
        pendingNumberSelectionTask = nil
        pendingNumberSelection = ""
    }

    // MARK: - Paste

    /// Places the item back on the pasteboard and pastes it into the previous app.
    ///
    /// The panel is left open so several items can be pasted in a row; it closes only via
    /// the status-item toggle.
    private func paste(_ item: ClipboardItem, closePanelAfterPaste: Bool = false) {
        // Always make the selection the current clipboard content first, so even
        // without the Accessibility permission a click still "copies" the item and
        // the user can ⌘V manually. Suppress so the monitor ignores our own write.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        monitor.suppressCurrentChange()

        // Without the permission we can't synthesize ⌘V; prompt once per session.
        guard AccessibilityPermission.isTrusted else {
            if !didPromptForAccessibility {
                didPromptForAccessibility = true
                AccessibilityPermission.request()
                AccessibilityPermission.openSettings()
            }
            return
        }

        guard let targetApp = previousApp else { return }

        if closePanelAfterPaste {
            closePanel()
        }

        Task {
            // The panel never took focus, so the target is normally already frontmost and
            // this fires immediately. The loop is a safety net: if anything did steal focus,
            // nudge the target frontmost and only paste once it's confirmed — never into
            // Clippy. Gives up quietly if focus never stabilizes.
            for _ in 0..<40 {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier else {
                    targetApp.activate()
                    try? await Task.sleep(for: .milliseconds(35))
                    continue
                }

                // Confirmed frontmost. Settle briefly, then re-verify right before pasting.
                try? await Task.sleep(for: .milliseconds(40))
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApp.processIdentifier {
                    Paster.simulateCommandV()
                    return
                }
            }
        }
    }

    // MARK: - Inline selection

    /// Resolves single- and multi-digit positions. Single digits wait briefly only when
    /// they could be the start of a later item (for example, 1 might become 10).
    private func selectNumberedItem(with digit: Int) {
        guard panel?.isVisible == true else { return }

        let candidate = pendingNumberSelection + String(digit)
        guard let position = Int(candidate), store.items.indices.contains(position - 1) else {
            pendingNumberSelection = ""
            pendingNumberSelectionTask?.cancel()
            pendingNumberSelectionTask = nil
            return
        }

        pendingNumberSelection = candidate
        pendingNumberSelectionTask?.cancel()

        // If an item with this number followed by another digit exists, wait for it.
        // Otherwise paste immediately, preserving the quick one-key flow for 2–9.
        guard store.items.count >= position * 10 else {
            pasteNumberedItem(at: position - 1)
            return
        }

        pendingNumberSelectionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self,
                  self.pendingNumberSelection == candidate else { return }
            self.pasteNumberedItem(at: position - 1)
        }
    }

    private func pasteNumberedItem(at index: Int) {
        pendingNumberSelectionTask?.cancel()
        pendingNumberSelectionTask = nil
        pendingNumberSelection = ""
        guard store.items.indices.contains(index) else { return }
        paste(store.items[index], closePanelAfterPaste: true)
    }

    private func makePanelContent(showsNumberHints: Bool) -> NSHostingView<PopoverContentView> {
        let content = PopoverContentView(store: store, showsNumberHints: showsNumberHints) { [weak self] item in
            self?.paste(item)
        }
        return NSHostingView(rootView: content)
    }

    /// Returns the focused editable element's screen frame, if Accessibility permits it.
    private func focusedTextInputFrame() -> NSRect? {
        guard AccessibilityPermission.isTrusted else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedElement = focusedValue as! AXUIElement? else {
            return nil
        }

        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &roleValue) == .success,
              let role = roleValue as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else {
            return nil
        }

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(focusedElement, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionAXValue = positionValue as! AXValue?,
              let sizeAXValue = sizeValue as! AXValue? else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size),
              let mainScreen = NSScreen.main else {
            return nil
        }

        // Accessibility coordinates originate at the upper-left of the main display;
        // AppKit screen coordinates originate at its lower-left.
        return NSRect(
            x: position.x,
            y: mainScreen.frame.maxY - position.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func panelOrigin(
        for focusedFieldFrame: NSRect?,
        size: NSSize,
        button: NSStatusBarButton,
        buttonWindow: NSWindow
    ) -> NSPoint {
        if let focusedFieldFrame,
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(focusedFieldFrame) }) {
            let visible = screen.visibleFrame
            let inset: CGFloat = 8
            let below = focusedFieldFrame.minY - size.height - inset
            let above = focusedFieldFrame.maxY + inset
            let y = below >= visible.minY + inset
                ? below
                : min(above, visible.maxY - size.height - inset)
            let x = min(
                max(focusedFieldFrame.minX, visible.minX + inset),
                visible.maxX - size.width - inset
            )
            return NSPoint(x: x, y: max(y, visible.minY + inset))
        }

        // Accessibility may be unavailable or the focused control may not be editable.
        // Retain the familiar menu-bar placement in those cases.
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        return NSPoint(
            x: min(max(buttonRect.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8),
            y: buttonRect.minY - size.height - 6
        )
    }
}
