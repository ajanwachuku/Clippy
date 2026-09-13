//
//  PopoverContentView.swift
//  Clippy
//
//  The SwiftUI content shown inside the menu bar panel.
//
//  Design direction: refined-utilitarian. Native macOS materials, a single accent,
//  SF Symbols, spring physics, and restrained micro-interactions — polished without
//  fighting the system look.
//
//  Note: there is deliberately no text field here. The content is hosted in a panel
//  that never becomes key (so it never steals focus from the app being pasted into),
//  and a text field can't work in a never-key window anyway.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Persistent draggable launcher. The history count updates as the store observes copies.
struct BubbleContentView: View {
    let store: ClipboardStore
    let onActivate: () -> Void

    var body: some View {
        ZStack {
            Image("ClippyBubble")
                .resizable()
                .interpolation(.high)
                .frame(width: 48, height: 48)
        }
        .frame(width: 56, height: 56)
        .overlay(alignment: .topTrailing) {
            if !store.items.isEmpty {
                Text("\(store.items.count)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Circle().fill(Color.accentColor))
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
            }
        }
        .overlay(PanelDragInteractionSurface(onActivate: onActivate))
        .accessibilityLabel("Clippy. \(store.items.count) clipboard items. Drag to reposition.")
    }
}

/// Provides one direct manipulation surface for the bubble: a click expands it and a drag
/// moves the containing panel. SwiftUI backgrounds do not reliably receive AppKit drag events.
private struct PanelDragInteractionSurface: NSViewRepresentable {
    let onActivate: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(onActivate: onActivate) }

    func makeNSView(context: Context) -> PanelDragInteractionView {
        PanelDragInteractionView(onActivate: context.coordinator.activate)
    }

    func updateNSView(_ nsView: PanelDragInteractionView, context: Context) {
        context.coordinator.onActivate = onActivate
        nsView.onActivate = context.coordinator.activate
    }

    final class Coordinator {
        var onActivate: (() -> Void)?
        init(onActivate: (() -> Void)?) { self.onActivate = onActivate }
        func activate() { onActivate?() }
    }
}

private final class PanelDragInteractionView: NSView {
    var onActivate: (() -> Void)?
    private var initialMouseLocation = NSPoint.zero
    private var initialWindowOrigin = NSPoint.zero
    private var didDrag = false

    init(onActivate: (() -> Void)?) {
        self.onActivate = onActivate
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        initialMouseLocation = window.convertPoint(toScreen: event.locationInWindow)
        initialWindowOrigin = window.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let location = window.convertPoint(toScreen: event.locationInWindow)
        let deltaX = location.x - initialMouseLocation.x
        let deltaY = location.y - initialMouseLocation.y
        if !didDrag, hypot(deltaX, deltaY) < 3 { return }
        didDrag = true
        window.setFrameOrigin(NSPoint(x: initialWindowOrigin.x + deltaX, y: initialWindowOrigin.y + deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag { onActivate?() }
    }
}

/// The clipboard history list, hover actions, and footer controls.
struct PopoverContentView: View {

    let store: ClipboardStore

    /// Shows the keyboard-selection labels when the panel was opened from an editable field.
    let showsNumberHints: Bool

    /// Invoked when a row is tapped; the app delegate performs the paste.
    var onPaste: (ClipboardItem) -> Void
    /// Returns the full picker to its persistent bubble.
    var onCollapse: () -> Void

    @State private var showingClearConfirmation = false
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var draggingItem: ClipboardItem?
    @State private var dropTargetID: ClipboardItem.ID?

    var body: some View {
        VStack(spacing: 0) {
            header

            content

            footer
        }
        .frame(width: 340, height: 460)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        )
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: store.items)
    }

    // MARK: - Content switch

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            emptyState
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
                .overlay(PanelDragInteractionSurface(onActivate: onCollapse))

            Text("Clippy")
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
        .frame(maxWidth: .infinity)
        .background(PanelDragInteractionSurface(onActivate: nil))
    }

    // MARK: - History

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                    ClipboardRow(
                        item: item,
                        number: showsNumberHints ? index + 1 : nil,
                        isDragging: draggingItem?.id == item.id,
                        isDropTarget: dropTargetID == item.id
                    ) {
                        onPaste(item)
                    } onDelete: {
                        store.delete(item)
                    }
                    .onDrag {
                        draggingItem = item
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    } preview: {
                        // Keep the lifted representation fixed while the live list reflows.
                        // The default preview snapshots the changing row and leaves ghost images.
                        ClipboardRow(
                            item: item,
                            number: showsNumberHints ? index + 1 : nil,
                            isDragging: false,
                            isDropTarget: false,
                            onPaste: {},
                            onDelete: {}
                        )
                        .frame(width: 316)
                    }
                    .onDrop(
                        of: [UTType.text.identifier],
                        delegate: ClipboardRowDropDelegate(
                            target: item,
                            draggingItem: $draggingItem,
                            dropTargetID: $dropTargetID,
                            store: store
                        )
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.92).combined(with: .opacity)
                    ))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .animation(.spring(response: 0.28, dampingFraction: 0.9), value: store.items)
        }
        .scrollIndicators(.never)
    }

    // MARK: - Empty state

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
                    // Skip no-op changes (e.g. the refresh below resyncing the state).
                    guard newValue != LoginItem.isEnabled else { return }
                    if !LoginItem.setEnabled(newValue) {
                        // Registration failed — show the true state, not the wish.
                        launchAtLogin = LoginItem.isEnabled
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .clippyPanelDidOpen)) { _ in
                    // The user may have changed this in System Settings while we were hidden.
                    launchAtLogin = LoginItem.isEnabled
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

private struct ClipboardRowDropDelegate: DropDelegate {
    let target: ClipboardItem
    @Binding var draggingItem: ClipboardItem?
    @Binding var dropTargetID: ClipboardItem.ID?
    let store: ClipboardStore

    func dropEntered(info: DropInfo) {
        guard let draggingItem, draggingItem.id != target.id else { return }
        guard let sourceIndex = store.items.firstIndex(of: draggingItem),
              let targetIndex = store.items.firstIndex(of: target) else { return }

        dropTargetID = target.id
        // A lower target means the dragged row belongs after it; a higher target means
        // it belongs before it. This lets the row travel fluidly in both directions.
        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            store.move(draggingItem, toOffset: destination)
        }
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == target.id {
            dropTargetID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        dropTargetID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

/// A single clipboard entry rendered as a self-contained, tappable card.
private struct ClipboardRow: View {

    let item: ClipboardItem
    let number: Int?
    let isDragging: Bool
    let isDropTarget: Bool
    var onPaste: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false

    private var kind: ClipboardItem.Kind { item.kind }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let number {
                Text("\(number)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(number <= 9 ? Color.accentColor : Color.secondary)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)
                    .accessibilityLabel(number <= 9
                        ? "Item \(number). Press \(number) to paste"
                        : "Item \(number). Type \(number) to paste")
            }

            // Content-type glyph.
            Image(systemName: kind.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(width: 16, height: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.previewText)
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

            // Delete reveals on hover.
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Delete")
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(Color.accentColor.opacity(0.12))
                                : AnyShapeStyle(Color.primary.opacity(0.045)))
                // Shadow lives on the background shape only, so hovering never casts a
                // drop shadow over the row's text (which read as a darkening in dark mode).
                .shadow(color: .black.opacity(isHovered ? 0.12 : 0), radius: 5, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDropTarget ? Color.accentColor.opacity(0.9)
                        : isHovered ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.06),
                    lineWidth: isDropTarget ? 2 : 1
                )
        )
        .opacity(isDragging ? 0.58 : 1)
        .scaleEffect(isDragging ? 0.985 : isHovered ? 1.012 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onPaste)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isDragging)
        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isDropTarget)
    }
}
