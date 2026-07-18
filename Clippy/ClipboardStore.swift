//
//  ClipboardStore.swift
//  Clippy
//
//  Holds the clipboard history and persists it to disk.
//

import Foundation
import Observation

/// Owns the list of `ClipboardItem`s and handles add / delete / clear / persistence.
///
/// History is persisted as JSON in Application Support so it survives relaunch.
@MainActor
@Observable
final class ClipboardStore {

    /// Most-recent-first list of captured items.
    private(set) var items: [ClipboardItem] = []

    /// Maximum number of items retained; oldest fall off the end.
    private let maxItems = 50

    /// Upper bound on the length of a single stored string (very large pastes are truncated).
    private let maxTextLength = 100_000

    private let saveURL: URL

    init() {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("Clippy", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        saveURL = directory.appendingPathComponent("history.json")
        load()
    }

    // MARK: - Mutations

    /// Adds a newly copied string to the top of the history.
    ///
    /// Skips empty / whitespace-only strings and consecutive duplicates of the most recent entry.
    func add(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Skip consecutive duplicates of the most recent entry.
        if let mostRecent = items.first, mostRecent.text == text { return }

        let stored = String(text.prefix(maxTextLength))
        items.insert(ClipboardItem(text: stored), at: 0)

        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        save()
    }

    /// Removes a single entry.
    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    /// Empties the entire history.
    func clear() {
        items.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            return
        }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: saveURL, options: [.atomic])
    }
}
