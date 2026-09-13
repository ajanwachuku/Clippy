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

    private static let savedPanelOriginKey = "savedPanelOrigin"
    /// The bubble has a 48px visual body plus a transparent 4px inset for its count badge.
    private static let bubbleSize = NSSize(width: 56, height: 56)
    private static let expandedSize = NSSize(width: 340, height: 460)

    private enum PanelMode {
        case bubble
        case expanded
    }

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
    private var isPlacingPanel = false
    private var panelMode: PanelMode = .bubble
    /// The collapsed bubble's stable location. The expanded frame may be clamped to a
    /// screen edge, but that temporary frame must never move the bubble.
    private var bubbleOrigin = NSPoint.zero

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
            button.action = #selector(expandPanel)
            button.target = self
        }
        statusItem = item
    }

    private func setupPanel() {
        let panel = ClipboardPanel(
            contentRect: NSRect(origin: .zero, size: Self.bubbleSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = makeBubbleContent()

        self.panel = panel
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: panel
        )
        showBubble()
    }

    /// ⌥⌘V expands the persistent bubble from anywhere. (Note: this shadows Finder's "Move Item Here" while
    /// Clippy runs; change the combination here if that bites.)
    private func setupHotKey() {
        HotKeyCenter.shared.register(
            keyCode: kVK_ANSI_V,
            carbonModifiers: cmdKey | optionKey
        ) { [weak self] in
            self?.expandPanel()
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

    @objc private func panelDidMove(_ note: Notification) {
        guard !isPlacingPanel, let panel else { return }
        let updatedBubbleOrigin = panelMode == .bubble
            ? panel.frame.origin
            : NSPoint(x: panel.frame.minX, y: panel.frame.maxY - Self.bubbleSize.height)
        bubbleOrigin = clampedOrigin(updatedBubbleOrigin, for: Self.bubbleSize)
        UserDefaults.standard.set(
            [Double(bubbleOrigin.x), Double(bubbleOrigin.y)],
            forKey: Self.savedPanelOriginKey
        )
    }

    // MARK: - Panel

    /// Expands the bubble in place. Repeated hotkey presses leave the full panel open.
    @objc private func expandPanel() {
        guard let panel, panelMode == .bubble else { return }

        let focusedFieldFrame = focusedTextInputFrame()
        let canSelectByNumber = focusedFieldFrame != nil && numberKeyInterceptor.start()
        bubbleOrigin = panel.frame.origin
        let topLeft = NSPoint(x: bubbleOrigin.x, y: bubbleOrigin.y + Self.bubbleSize.height)
        let origin = clampedOrigin(
            NSPoint(x: topLeft.x, y: topLeft.y - Self.expandedSize.height),
            for: Self.expandedSize
        )
        isPlacingPanel = true
        panel.setFrame(NSRect(origin: origin, size: Self.expandedSize), display: true, animate: false)
        isPlacingPanel = false
        panel.hasShadow = true
        panel.contentView = makePanelContent(showsNumberHints: canSelectByNumber)
        panelMode = .expanded

        // Order front WITHOUT activating Clippy or making the panel key, so the target app keeps focus.
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
                self?.collapseToBubble()
            }
        }
    }

    /// Keeps Clippy available while returning from the full picker to its compact bubble.
    private func collapseToBubble() {
        guard let panel, panelMode == .expanded else { return }
        isPlacingPanel = true
        panel.setFrame(NSRect(origin: bubbleOrigin, size: Self.bubbleSize), display: true, animate: false)
        isPlacingPanel = false
        panel.hasShadow = false
        panel.contentView = makeBubbleContent()
        panelMode = .bubble
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
    /// The panel remains open so several items can be pasted in a row; Escape collapses it.
    private func paste(_ item: ClipboardItem) {
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
        paste(store.items[index])
    }

    private func makePanelContent(showsNumberHints: Bool) -> NSHostingView<PopoverContentView> {
        let content = PopoverContentView(
            store: store,
            showsNumberHints: showsNumberHints,
            onPaste: { [weak self] item in self?.paste(item) },
            onCollapse: { [weak self] in self?.collapseToBubble() }
        )
        return NSHostingView(rootView: content)
    }

    private func makeBubbleContent() -> NSHostingView<BubbleContentView> {
        NSHostingView(rootView: BubbleContentView(store: store) { [weak self] in
            self?.expandPanel()
        })
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

    private func showBubble() {
        guard let panel else { return }
        let defaultOrigin: NSPoint
        if let visible = NSScreen.main?.visibleFrame {
            defaultOrigin = NSPoint(x: visible.maxX - Self.bubbleSize.width - 20, y: visible.minY + 20)
        } else {
            defaultOrigin = .zero
        }
        let origin = savedPanelOrigin(for: Self.bubbleSize) ?? defaultOrigin
        bubbleOrigin = origin
        isPlacingPanel = true
        panel.setFrame(NSRect(origin: origin, size: Self.bubbleSize), display: true)
        isPlacingPanel = false
        panel.orderFrontRegardless()
    }

    private func clampedOrigin(_ origin: NSPoint, for size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(NSRect(origin: origin, size: size)) })
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        return NSPoint(
            x: min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8),
            y: min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        )
    }

    /// Restores a manually dragged bubble position and keeps it visible after a display change.
    private func savedPanelOrigin(for size: NSSize) -> NSPoint? {
        guard let values = UserDefaults.standard.array(forKey: Self.savedPanelOriginKey),
              values.count == 2,
              let x = values[0] as? NSNumber,
              let y = values[1] as? NSNumber else {
            return nil
        }

        let origin = NSPoint(x: x.doubleValue, y: y.doubleValue)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(origin) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return nil }
        return NSPoint(
            x: min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8),
            y: min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        )
    }
}
