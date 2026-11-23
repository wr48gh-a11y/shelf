import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

enum ComposerMode: Equatable {
    case add(prefill: String?)
    case edit(PinItem)
}

@MainActor
@Observable
final class ShelfUIState {
    var filterText: String = ""
    var selectedIndex: Int? = nil
    var hoveredItemID: UUID? = nil
    var composerMode: ComposerMode? = nil
    var showSettings: Bool = false
    var draggedItemID: UUID? = nil

    func resetForOpen(openComposer: Bool = false) {
        filterText = ""
        selectedIndex = nil
        hoveredItemID = nil
        showSettings = false
        draggedItemID = nil
        composerMode = openComposer ? .add(prefill: nil) : nil
    }

    func filteredItems(from all: [PinItem]) -> [PinItem] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.label.localizedCaseInsensitiveContains(q) ||
            $0.value.localizedCaseInsensitiveContains(q)
        }
    }
}

struct ShelfPopoverView: View {
    @Bindable var store: ShelfStore
    @Bindable var ui: ShelfUIState
    @Bindable var hotKeyManager: HotKeyManager
    @Bindable var launchAtLogin: LaunchAtLoginManager

    let onCopyAndDismiss: (PinItem) -> Void
    let onOpenURLAndDismiss: (PinItem) -> Void
    let onQuit: () -> Void
    let onHeightChange: (CGFloat) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var visibleItems: [PinItem] {
        ui.filteredItems(from: store.items)
    }

    private var peekItem: PinItem? {
        if let copiedID = store.copiedItemID,
           let item = store.items.first(where: { $0.id == copiedID }) {
            return item
        }
        if let hoveredID = ui.hoveredItemID,
           let item = visibleItems.first(where: { $0.id == hoveredID }) {
            return item
        }
        if let selectedIndex = ui.selectedIndex,
           visibleItems.indices.contains(selectedIndex) {
            return visibleItems[selectedIndex]
        }
        return nil
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.08)
    }

    private var outerBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.17) : Color.black.opacity(0.10)
    }

    private var glassTint: Color {
        colorScheme == .dark
            ? Color(red: 0.06, green: 0.07, blue: 0.10).opacity(0.46)
            : Color.white.opacity(0.42)
    }

    /// Cap the scroll area around 11 visible rows (~340pt) so even 20 pins stay compact.
    private var listHeight: CGFloat {
        let rowSlot: CGFloat = 32
        let count = max(1, visibleItems.count)
        let natural = CGFloat(count) * rowSlot
        return min(natural, 344)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Rectangle()
                .fill(dividerColor)
                .frame(height: 0.75)

            // Hidden-by-default live type-to-filter pill
            if !ui.filterText.isEmpty && ui.composerMode == nil && !ui.showSettings {
                filterPill
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Inline Settings Drawer
            if ui.showSettings {
                SettingsDrawerView(
                    hotKeyManager: hotKeyManager,
                    launchAtLogin: launchAtLogin,
                    store: store,
                    onClose: {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                            ui.showSettings = false
                        }
                    },
                    onQuit: onQuit
                )
                .padding(.horizontal, 8)
                .padding(.top, 7)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Inline Add / Edit Composer
            if let mode = ui.composerMode {
                Group {
                    switch mode {
                    case .add(let prefill):
                        PinComposerView(
                            editingItem: nil,
                            prefillValue: prefill,
                            onSave: { label, value, accent in
                                let saved = store.add(label: label, value: value, accent: accent)
                                if saved {
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                        ui.composerMode = nil
                                    }
                                }
                                // On failure the composer stays open with the input
                                // intact and shows the inline error for an immediate retry.
                                return saved
                            },
                            onCancel: {
                                store.clearTransientSaveError()
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                                    ui.composerMode = nil
                                }
                            }
                        )
                    case .edit(let item):
                        PinComposerView(
                            editingItem: item,
                            onSave: { label, value, accent in
                                let saved = store.update(id: item.id, label: label, value: value, accent: accent)
                                if saved {
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                        ui.composerMode = nil
                                    }
                                }
                                return saved
                            },
                            onCancel: {
                                store.clearTransientSaveError()
                                withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                                    ui.composerMode = nil
                                }
                            }
                        )
                    }
                }
                .id(mode == .add(prefill: nil) ? "add" : "edit-\(String(describing: mode))")
                .padding(.horizontal, 8)
                .padding(.top, 7)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Main Pins List, Load-Failure Recovery, or Empty State
            if store.isStorageBlocked && ui.composerMode == nil && !ui.showSettings {
                storageBlockedView
            } else if store.items.isEmpty && ui.composerMode == nil && !ui.showSettings {
                emptyStateView
            } else if visibleItems.isEmpty && !ui.filterText.isEmpty {
                noMatchesView
            } else if !visibleItems.isEmpty {
                ScrollView(.vertical, showsIndicators: visibleItems.count > 10) {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(visibleItems.enumerated()), id: \.element.id) { idx, item in
                            let shortcutNum: Int? = ui.filterText.isEmpty ? (idx + 1) : (idx + 1)
                            PinRowView(
                                item: item,
                                shortcutIndex: shortcutNum,
                                isCopied: store.copiedItemID == item.id,
                                isHovered: ui.hoveredItemID == item.id,
                                isSelected: ui.selectedIndex == idx,
                                isDragging: ui.draggedItemID == item.id,
                                onCopy: { onCopyAndDismiss(item) },
                                onOpenURL: { onOpenURLAndDismiss(item) },
                                onEdit: {
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                        ui.showSettings = false
                                        ui.composerMode = .edit(item)
                                    }
                                },
                                onDelete: {
                                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                                        if ui.hoveredItemID == item.id { ui.hoveredItemID = nil }
                                        store.delete(id: item.id)
                                    }
                                },
                                onHoverChange: { hovering in
                                    if hovering {
                                        ui.hoveredItemID = item.id
                                    } else if ui.hoveredItemID == item.id {
                                        ui.hoveredItemID = nil
                                    }
                                }
                            )
                            .onDrag {
                                ui.draggedItemID = item.id
                                return NSItemProvider(object: item.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: PinDropDelegate(
                                    targetItem: item,
                                    draggedItemID: $ui.draggedItemID,
                                    onMove: { fromID, toID in
                                        if ui.filterText.isEmpty {
                                            store.move(fromID: fromID, toID: toID)
                                        }
                                    }
                                )
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .frame(height: listHeight + 12)
            }

            Rectangle()
                .fill(dividerColor)
                .frame(height: 0.75)

            whisperPeekFooter
        }
        .frame(width: 272)
        .background(
            ZStack {
                VisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)
                glassTint
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(outerBorderColor, lineWidth: 0.9)
        )
        .overlay(
            // Subtle top specular highlight (2025-2026 glass craft)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.22 : 0.75),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 0.75
                )
                .padding(0.5)
        )
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            if newHeight > 40 {
                onHeightChange(newHeight)
            }
        }
    }

    // MARK: - Subviews

    private var headerBar: some View {
        HStack(spacing: 6) {
            Text("Shelf")
                .font(.system(size: 12.5, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Color.primary)

            Text("\(store.items.count)/\(ShelfStore.maxItems)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(store.isFull ? Color.orange : Color.secondary)

            Spacer()

            HeaderIconButton(
                systemName: ui.showSettings ? "xmark" : "ellipsis",
                helpText: "Preferences & Quit (⌘,)",
                isActive: ui.showSettings
            ) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    ui.composerMode = nil
                    ui.showSettings.toggle()
                }
            }

            HeaderIconButton(
                systemName: ui.composerMode != nil ? "xmark" : "plus",
                helpText: store.isStorageBlocked && ui.composerMode == nil
                    ? "Saved pins could not be read"
                    : (store.isFull && ui.composerMode == nil
                        ? "Shelf is full (20/20)"
                        : (ui.composerMode != nil ? "Close editor (Esc)" : "New Pin (⌘N)")),
                isActive: ui.composerMode != nil,
                isDisabled: (store.isFull || store.isStorageBlocked) && ui.composerMode == nil
            ) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    ui.showSettings = false
                    if ui.composerMode != nil {
                        store.clearTransientSaveError()
                        ui.composerMode = nil
                    } else if !store.isFull && !store.isStorageBlocked {
                        ui.composerMode = .add(prefill: nil)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private var filterPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.secondary)

            Text(ui.filterText)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    ui.filterText = ""
                    ui.selectedIndex = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Clear filter (Esc)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        )
    }

    /// Whisper recovery panel shown when pins.json exists but could not be read.
    private var storageBlockedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.orange)

            Text("Couldn't read saved pins")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.primary)

            Text(store.loadError ?? "pins.json could not be read and was left untouched.")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Button {
                    store.retryLoad()
                } label: {
                    Text("Retry")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
                .help("Try reading pins.json again")

                Button {
                    store.backupAndResetStorage()
                } label: {
                    Text("Back Up & Reset")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(Color.orange.opacity(colorScheme == .dark ? 0.16 : 0.11))
                        )
                }
                .buttonStyle(.plain)
                .help("Copy pins.json to a timestamped backup, then start a fresh shelf")
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.secondary.opacity(0.75))

            Text("No pins yet")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.primary)

            Text("Pin up to 20 links, emails, or snippets for instant copy.")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        ui.composerMode = .add(prefill: nil)
                    }
                } label: {
                    Text("+ New Pin")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)

                if let clip = NSPasteboard.general.string(forType: .string),
                   !clip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                            ui.composerMode = .add(prefill: clip)
                        }
                    } label: {
                        Text("Pin Clipboard")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.07))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
    }

    private var noMatchesView: some View {
        VStack(spacing: 4) {
            Text("No matching pins")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondary)
            Text("Press Esc to clear filter")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.secondary.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var whisperPeekFooter: some View {
        HStack(spacing: 6) {
            if store.copiedItemID != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.green)
                Text("Copied to clipboard")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.green)
                    .lineLimit(1)
            } else if store.saveError != nil {
                // Persistence failed: surface it instead of acknowledging silently.
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.orange)
                Text(store.saveError ?? "")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if store.hasUnsavedChanges {
                    Button("Retry") {
                        store.retrySave()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .help("Try saving again")
                }
            } else if let deleted = store.lastDeleted {
                Text("Removed \"\(deleted.item.label)\"")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Button("Undo") {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                        _ = store.undoDelete()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            } else if let peek = peekItem {
                Text(peek.singleLinePreview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(idleFooterText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.78))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private var idleFooterText: String {
        if store.items.isEmpty {
            return hotKeyManager.preset == .off ? "⌘N to add a pin" : "\(hotKeyManager.preset.displayLabel) to open · ⌘N to add"
        }
        return hotKeyManager.preset == .off
            ? "Hover to peek · Type to filter"
            : "Hover to peek · \(hotKeyManager.preset.displayLabel)"
    }
}

private struct HeaderIconButton: View {
    let systemName: String
    let helpText: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(
                    isDisabled
                        ? Color.secondary.opacity(0.35)
                        : (isActive || isHovered ? Color.primary : Color.secondary)
                )
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(
                            isActive || isHovered
                                ? (colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.08))
                                : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(helpText)
        .onHover { isHovered = $0 }
    }
}
