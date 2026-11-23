import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsDrawerView: View {
    @Bindable var hotKeyManager: HotKeyManager
    @Bindable var launchAtLogin: LaunchAtLoginManager
    let store: ShelfStore
    let onClose: () -> Void
    let onQuit: () -> Void

    @State private var transferStatus: String? = nil
    @Environment(\.colorScheme) private var colorScheme

    private var cardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.065) : Color.black.opacity(0.04)
    }

    private var borderStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.09)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Preferences")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
                Button("Done") { onClose() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            // Global Hotkey Preset Picker
            VStack(alignment: .leading, spacing: 5) {
                Text("Global Shortcut")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.secondary)

                HStack(spacing: 4) {
                    ForEach(HotKeyPreset.allCases) { preset in
                        let active = hotKeyManager.preset == preset
                        Button {
                            hotKeyManager.preset = preset
                        } label: {
                            Text(preset.displayLabel)
                                .font(.system(size: 11, weight: active ? .semibold : .regular, design: .monospaced))
                                .foregroundStyle(active ? Color.white : Color.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(
                                            active
                                                ? Color.accentColor
                                                : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(preset.description)
                    }
                }
            }

            Divider().opacity(0.5)

            // Launch at Login
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Launch at Login")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                }
                if let note = launchAtLogin.statusNote {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
            }

            Divider().opacity(0.5)

            // Backup & Restore + Quit
            HStack(spacing: 6) {
                Button {
                    exportPins()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .disabled(store.items.isEmpty)

                Button {
                    importPins()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    onQuit()
                } label: {
                    Text("Quit")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.red.opacity(colorScheme == .dark ? 0.16 : 0.10))
                        )
                }
                .buttonStyle(.plain)
            }

            if let transferStatus {
                Text(transferStatus)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(borderStroke, lineWidth: 0.75)
                )
        )
    }

    private func exportPins() {
        guard let data = store.exportJSON() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "shelf-pins.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url, options: .atomic)
                transferStatus = "Exported \(store.items.count) pins."
            } catch {
                transferStatus = "Export failed."
            }
        }
    }

    private func importPins() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url) {
            let count = store.importJSON(data)
            transferStatus = count > 0 ? "Imported \(count) pin\(count == 1 ? "" : "s")." : "No new pins imported."
        }
    }
}
