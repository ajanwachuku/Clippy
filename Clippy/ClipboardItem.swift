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

// MARK: - Presentation

extension ClipboardItem {

    /// A coarse classification of the entry's content, used to pick a row glyph and font.
    enum Kind {
        case url, email, code, number, text

        /// SF Symbol name representing the kind.
        var symbol: String {
            switch self {
            case .url:    return "link"
            case .email:  return "envelope"
            case .code:   return "chevron.left.forwardslash.chevron.right"
            case .number: return "number"
            case .text:   return "text.alignleft"
            }
        }
    }

    /// Heuristic content classification based on the trimmed text.
    var kind: Kind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
           !trimmed.contains(" ") {
            return .url
        }
        if !trimmed.contains(" "), !trimmed.contains("\n"),
           trimmed.contains("@"), trimmed.contains("."),
           trimmed.count <= 254 {
            return .email
        }
        if !trimmed.isEmpty,
           trimmed.allSatisfy({ $0.isNumber || "+-.,()$€£% ".contains($0) }),
           trimmed.contains(where: \.isNumber) {
            return .number
        }
        // Looks like code if it spans multiple lines and carries typical code punctuation.
        if trimmed.contains("\n"),
           trimmed.contains(where: { "{}[];=<>".contains($0) }) {
            return .code
        }
        return .text
    }

    /// A short size label for the row metadata (line count for multi-line, else characters).
    var metricLabel: String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        if lines > 1 {
            return "\(lines) lines"
        }
        let count = text.count
        return count == 1 ? "1 char" : "\(count) chars"
    }
}
