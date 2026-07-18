//
//  ClipboardMonitor.swift
//  Clippy
//
//  Watches the system pasteboard for new copies.
//

import AppKit

/// Polls `NSPasteboard.general` on a timer and forwards new text to the store.
@MainActor
final class ClipboardMonitor {

    private let store: ClipboardStore
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var pollingTask: Task<Void, Never>?

    /// How often the pasteboard is checked for changes.
    private let interval: Duration = .milliseconds(500)

    init(store: ClipboardStore) {
        self.store = store
        self.lastChangeCount = pasteboard.changeCount
    }

    /// Begins polling. Safe to call more than once.
    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: self?.interval ?? .milliseconds(500))
            }
        }
    }

    /// Stops polling.
    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Marks the current pasteboard state as already seen.
    ///
    /// Called right after Clippy writes to the pasteboard itself (e.g. when pasting an
    /// item), so the monitor does not re-capture our own write as a brand-new copy.
    func suppressCurrentChange() {
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        if let string = pasteboard.string(forType: .string) {
            store.add(string)
        }
    }
}
