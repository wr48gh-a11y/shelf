import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ShelfStore {
    static let maxItems = 20

    var items: [PinItem] = []
    var lastDeleted: (item: PinItem, index: Int)? = nil
    var copiedItemID: UUID? = nil

    private var undoTimer: Timer?
    private var copyFeedbackTimer: Timer?
    private let storageURL: URL

    var onCopiedFeedback: (() -> Void)?

    init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            let dir = appSupport.appendingPathComponent("Shelf", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.storageURL = dir.appendingPathComponent("pins.json")
        }
        load()
    }

    var isFull: Bool {
        items.count >= Self.maxItems
    }

    var remainingSlots: Int {
        max(0, Self.maxItems - items.count)
    }

    @discardableResult
    func add(label: String, value: String, accent: WhisperAccent?) -> Bool {
        guard !isFull else { return false }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedValue = value.trimmingCharacters(in: .newlines)
        guard !trimmedLabel.isEmpty, !cleanedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let item = PinItem(label: trimmedLabel, value: cleanedValue, accent: accent)
        items.append(item)
        save()
        return true
    }

    func update(id: UUID, label: String, value: String, accent: WhisperAccent) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items[idx].label = trimmedLabel
        items[idx].value = value
        items[idx].accent = accent
        save()
    }

    func delete(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let removed = items.remove(at: idx)
        save()

        lastDeleted = (removed, idx)
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.lastDeleted = nil
            }
        }
    }

    func undoDelete() {
        guard let deleted = lastDeleted, !isFull else {
            lastDeleted = nil
            return
        }
        let insertIndex = min(deleted.index, items.count)
        items.insert(deleted.item, at: insertIndex)
        lastDeleted = nil
        undoTimer?.invalidate()
        save()
    }

    func move(fromID: UUID, toID: UUID) {
        guard fromID != toID,
              let fromIndex = items.firstIndex(where: { $0.id == fromID }),
              let toIndex = items.firstIndex(where: { $0.id == toID }) else { return }
        let moved = items.remove(at: fromIndex)
        items.insert(moved, at: toIndex)
        save()
    }

    func copy(_ item: PinItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.value, forType: .string)

        copiedItemID = item.id
        onCopiedFeedback?()

        copyFeedbackTimer?.invalidate()
        copyFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 0.95, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.copiedItemID = nil
            }
        }
    }

    func openURL(for item: PinItem) {
        guard let url = item.openableURL else { return }
        NSWorkspace.shared.open(url)
    }

    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(items)
    }

    func importJSON(_ data: Data) -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let imported = try? decoder.decode([PinItem].self, from: data) else { return 0 }
        let existingValues = Set(items.map { $0.value })
        var added = 0
        for item in imported {
            if isFull { break }
            if !existingValues.contains(item.value) {
                items.append(PinItem(label: item.label, value: item.value, accent: item.accent))
                added += 1
            }
        }
        if added > 0 { save() }
        return added
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            items = []
            return
        }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([PinItem].self, from: data)
            items = Array(decoded.prefix(Self.maxItems))
        } catch {
            items = []
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Array(items.prefix(Self.maxItems)))
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            // Silently ignore write failures in UI; path is standard Application Support
        }
    }
}
