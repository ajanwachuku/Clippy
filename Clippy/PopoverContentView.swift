//
//  PopoverContentView.swift
//  Clippy
//
//  The SwiftUI content shown inside the menu bar popover.
//
//  Design direction: refined-utilitarian. Native macOS materials, a single accent,
//  SF Symbols, spring physics, and restrained micro-interactions — polished without
//  fighting the system look.
//

import SwiftUI
import AppKit

/// The clipboard history list, live search, hover actions, and footer controls.
struct PopoverContentView: View {

    let store: ClipboardStore

    /// Invoked when a row is tapped; the app delegate performs the paste.
    var onPaste: (ClipboardItem) -> Void

    @State private var showingClearConfirmation = false
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    /// History filtered by the live search query (case-insensitive substring).
    private var filteredItems: [ClipboardItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.items }
        return store.items.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if !store.items.isEmpty {
                searchField
                Divider().opacity(0.5)
            }

            content

            footer
        }
        .frame(width: 340, height: 460)
        .background(.regularMaterial)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: store.items)
        .animation(.easeOut(duration: 0.18), value: query)
    }

    // MARK: - Content switch

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            emptyState
        } else if filteredItems.isEmpty {
            noResultsState
        } else {
            historyList
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "paperclip")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.gradient)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 3, y: 1)
                )

            Text("Clipboard")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            if !store.items.isEmpty {
                Text("\(store.items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
                    .contentTransition(.numericText())
            }

            Spacer()

            Button {
                showingClearConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(store.items.isEmpty)
            .help("Clear all history")
            .confirmationDialog(
                "Clear all clipboard history?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) { store.clear() }
                Button("Cancel", role: .cancel) { }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 10)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search history", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit {
                    if let first = filteredItems.first { onPaste(first) }
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: - History

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(filteredItems) { item in
                    ClipboardRow(item: item) {
                        onPaste(item)
                    } onDelete: {
                        store.delete(item)
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.92).combined(with: .opacity)
                    ))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
    }

    // MARK: - Empty & no-results states

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clipboard")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
                .symbolEffect(.pulse, options: .repeating)
            Text("No clipboard history yet")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Copy something and it'll show up here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No matches for “\(query)”")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItem.setEnabled(newValue)
                }

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Quit Clippy")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.4))
    }
}

// MARK: - Row

/// A single clipboard entry rendered as a self-contained, tappable card.
private struct ClipboardRow: View {

    let item: ClipboardItem
    var onPaste: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false
    @State private var didCopy = false

    private var kind: ClipboardItem.Kind { item.kind }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Content-type glyph.
            Image(systemName: kind.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 16, height: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(kind == .code ? .system(size: 12.5, design: .monospaced) : .callout)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(item.createdAt.formatted(.relative(presentation: .numeric)))
                    Text("·")
                    Text(item.metricLabel)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            // Actions reveal on hover.
            if isHovered {
                HStack(spacing: 2) {
                    Button(action: copy) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(didCopy ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                            .frame(width: 20, height: 20)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .help("Copy")

                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(Color.accentColor.opacity(0.12))
                                : AnyShapeStyle(Color.primary.opacity(0.045)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isHovered ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(isHovered ? 0.12 : 0), radius: 5, y: 2)
        .scaleEffect(isHovered ? 1.012 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onPaste)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovered)
        .animation(.easeInOut(duration: 0.2), value: didCopy)
    }

    /// Copies the entry's text to the pasteboard and shows a brief confirmation.
    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            didCopy = false
        }
    }
}
