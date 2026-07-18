//
//  ClipboardItem.swift
//  Clippy
//
//  A single captured clipboard entry.
//

import Foundation

/// One entry in the clipboard history.
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}
