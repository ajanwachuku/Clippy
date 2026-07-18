//
//  AccessibilityPermission.swift
//  Clippy
//
//  Helpers around the Accessibility (AX) permission required to synthesize keystrokes.
//

import AppKit
import ApplicationServices

/// Wraps the Accessibility permission checks used before synthesizing ⌘V.
enum AccessibilityPermission {

    /// Whether the app is currently trusted to control the computer via Accessibility.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user for Accessibility permission (shows the system dialog once).
    @discardableResult
    static func request() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings directly to the Accessibility privacy pane.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
