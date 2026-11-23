import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PinRowView: View {
    let item: PinItem
    let shortcutIndex: Int? // 1...9 when shown
    let isCopied: Bool
    let isHovered: Bool
    let isSelected: Bool
    let isDragging: Bool
    let onCopy: () -> Void
    let onOpenURL: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onHoverChange: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var isHighlighted: Bool {
        isHovered || isSelected
    }

    private var rowBackground: Color {
        if isCopied {
            return Color.green.opacity(colorScheme == .dark ? 0.22 : 0.15)
        }
        if isHighlighted {
            return colorScheme == .dark
                ? Color.white.opacity(0.11)
                : Color.black.opacity(0.06)
        }
        return Color.clear
    }

    var body: some View {
        HStack(spacing: 8) {
            // Mini book spine (tips out on hover, morphs into checkmark on copy)
            ZStack {
                if isCopied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Color.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(item.accent.color)
                        .frame(width: 3.2, height: 13)
                        .shadow(
                            color: isHighlighted ? item.accent.color.opacity(0.5) : .clear,
                            radius: 3.5
                        )
                        .rotationEffect(.degrees(isHighlighted ? -10 : 0), anchor: .bottom)
                        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isHighlighted)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 12, height: 12)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isCopied)

            // Single-line Whisper label
            Text(item.label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isCopied ? (colorScheme == .dark ? Color(red: 0.55, green: 0.96, blue: 0.76) : Color(red: 0.04, green: 0.50, blue: 0.30)) : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // Trailing slot: Copied check, Hover micro-actions, or quiet ⌘1-⌘9 hint
            if isCopied {
                Text("✓")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.green)
                    .transition(.opacity)
            } else if isHovered {
                HStack(spacing: 2) {
                    if item.openableURL != nil {
                        MicroIconButton(
                            systemName: "arrow.up.right",
                            helpText: "Open link in browser (⌥Click)",
                            action: onOpenURL
                        )
                    }
                    MicroIconButton(
                        systemName: "pencil",
                        helpText: "Edit on shelf",
                        action: onEdit
                    )
                    MicroIconButton(
                        systemName: "xmark",
                        helpText: "Take off shelf",
                        isDestructive: true,
                        action: onDelete
                    )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else if let shortcutIndex, shortcutIndex <= 9 {
                Text("⌘\(shortcutIndex)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.75))
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(isDragging ? 0.35 : 1.0)
        .onHover { hovering in
            onHoverChange(hovering)
        }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.option), item.openableURL != nil {
                onOpenURL()
            } else {
                onCopy()
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

private struct MicroIconButton: View {
    let systemName: String
    let helpText: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isOver = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(
                    isOver && isDestructive
                        ? Color.red
                        : (isOver ? Color.primary : Color.secondary)
                )
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            isOver
                                ? (colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                                : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { isOver = $0 }
    }
}

struct PinDropDelegate: DropDelegate {
    let targetItem: PinItem
    @Binding var draggedItemID: UUID?
    let onMove: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let fromID = draggedItemID, fromID != targetItem.id else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            onMove(fromID, targetItem.id)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItemID = nil
        return true
    }
}
