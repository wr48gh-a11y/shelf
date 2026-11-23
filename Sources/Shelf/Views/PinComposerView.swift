import AppKit
import SwiftUI

struct PinComposerView: View {
    let editingItem: PinItem?
    let onSave: (_ label: String, _ value: String, _ accent: WhisperAccent) -> Void
    let onCancel: () -> Void

    @State private var label: String
    @State private var value: String
    @State private var accent: WhisperAccent
    @State private var userPickedAccent: Bool

    @FocusState private var focusedField: Field?
    @Environment(\.colorScheme) private var colorScheme

    private enum Field {
        case label
        case value
    }

    init(
        editingItem: PinItem? = nil,
        prefillValue: String? = nil,
        onSave: @escaping (_ label: String, _ value: String, _ accent: WhisperAccent) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.editingItem = editingItem
        self.onSave = onSave
        self.onCancel = onCancel

        if let editingItem {
            _label = State(initialValue: editingItem.label)
            _value = State(initialValue: editingItem.value)
            _accent = State(initialValue: editingItem.accent)
            _userPickedAccent = State(initialValue: true)
        } else if let prefillValue, !prefillValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let suggested = Self.suggestLabel(from: prefillValue)
            let detected = PinKind.detect(from: prefillValue)
            _label = State(initialValue: suggested)
            _value = State(initialValue: prefillValue)
            _accent = State(initialValue: WhisperAccent.defaultAccent(for: detected))
            _userPickedAccent = State(initialValue: false)
        } else {
            _label = State(initialValue: "")
            _value = State(initialValue: "")
            _accent = State(initialValue: .sky)
            _userPickedAccent = State(initialValue: false)
        }
    }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var surfaceFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.065) : Color.black.opacity(0.04)
    }

    private var fieldFill: Color {
        colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.75)
    }

    private var borderStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(editingItem == nil ? "New Pin" : "Edit Pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                Spacer()
                Button {
                    pasteFromClipboard()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10))
                        Text("Paste")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .help("Fill from current clipboard")
            }

            // Label field
            TextField("Label (e.g. Calendly 30m)", text: $label)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 5.5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(fieldFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(borderStroke, lineWidth: 0.75)
                        )
                )
                .focused($focusedField, equals: .label)
                .onSubmit {
                    if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        focusedField = .value
                    } else if canSave {
                        commit()
                    }
                }

            // Value field (supports multi-line paste, single-line compact presentation)
            TextField("URL, email, or snippet…", text: $value, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                .lineLimit(1...3)
                .padding(.horizontal, 8)
                .padding(.vertical, 5.5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(fieldFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(borderStroke, lineWidth: 0.75)
                        )
                )
                .focused($focusedField, equals: .value)
                .onChange(of: value) { _, newValue in
                    if !userPickedAccent {
                        let kind = PinKind.detect(from: newValue)
                        accent = WhisperAccent.defaultAccent(for: kind)
                    }
                }
                .onSubmit {
                    if canSave {
                        commit()
                    }
                }

            // Bottom row: Accent dot picker + Cancel / Save
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    ForEach(WhisperAccent.allCases) { option in
                        Button {
                            accent = option
                            userPickedAccent = true
                        } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 9, height: 9)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(accent == option ? 0.85 : 0), lineWidth: 1.5)
                                        .frame(width: 13, height: 13)
                                )
                                .frame(width: 15, height: 15)
                        }
                        .buttonStyle(.plain)
                        .help(option.label)
                    }
                }

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)

                Button {
                    commit()
                } label: {
                    Text(editingItem == nil ? "Pin" : "Save")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(canSave ? Color.accentColor : Color.secondary.opacity(0.35))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
            .padding(.top, 1)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(surfaceFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(borderStroke, lineWidth: 0.75)
                )
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                focusedField = .label
            }
        }
    }

    func commitIfValid() {
        if canSave { commit() }
    }

    private func commit() {
        onSave(label, value, accent)
    }

    private func pasteFromClipboard() {
        guard let raw = NSPasteboard.general.string(forType: .string),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        value = raw
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            label = Self.suggestLabel(from: raw)
        }
        if !userPickedAccent {
            accent = WhisperAccent.defaultAccent(for: PinKind.detect(from: raw))
        }
        focusedField = .label
    }

    static func suggestLabel(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = PinKind.detect(from: trimmed)
        switch kind {
        case .url:
            let withScheme = trimmed.lowercased().hasPrefix("http") ? trimmed : "https://\(trimmed)"
            if let host = URL(string: withScheme)?.host {
                let clean = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                let base = clean.split(separator: ".").first.map(String.init) ?? clean
                return base.prefix(1).uppercased() + base.dropFirst()
            }
            return String(trimmed.prefix(24))
        case .email:
            return "Email"
        case .snippet:
            let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
            if firstLine.count <= 22 { return firstLine }
            return String(firstLine.prefix(21)) + "…"
        }
    }
}
