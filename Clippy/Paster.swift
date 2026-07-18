//
//  Paster.swift
//  Clippy
//
//  Writes to the pasteboard and synthesizes a ⌘V keystroke.
//

import AppKit

/// Handles placing text on the pasteboard and simulating a paste into the frontmost app.
enum Paster {

    /// Virtual key code for the "V" key (kVK_ANSI_V).
    private static let vKeyCode: CGKeyCode = 0x09

    /// Synthesizes a ⌘V key-down / key-up so the frontmost app pastes.
    ///
    /// Requires Accessibility permission; posting silently no-ops if the event
    /// source cannot be created.
    static func simulateCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
