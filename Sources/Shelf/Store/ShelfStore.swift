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

    /// Non-nil when pins.json exists but could not be read or decoded. The file is
    /// preserved untouched and all mutations are refused until the user recovers.
    var loadError: String? = nil
    var isStorageBlocked: Bool { loadError != nil }

    /// Non-nil when the most recent save failed. Cleared again by a successful save.
    var saveError: String? = nil
    /// True when in-memory items contain changes that never reached disk.
    var hasUnsavedChanges: Bool = false

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
        guard !isStorageBlocked, !isFull else { return false }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedValue = value.trimmingCharacters(in: .newlines)
        guard !trimmedLabel.isEmpty, !cleanedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let item = PinItem(label: trimmedLabel, value: cleanedValue, accent: accent)
        items.append(item)
        guard save() else {
            // Revert so memory stays consistent with disk; the composer stays open
            // with the user's input intact and shows the error for an immediate retry.
            items.removeLast()
            return false
        }
        return true
    }

    @discardableResult
    func update(id: UUID, label: String, value: String, accent: WhisperAccent) -> Bool {
        guard !isStorageBlocked,
              let idx = items.firstIndex(where: { $0.id == id }) else { return false }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let previous = items[idx]
        items[idx].label = trimmedLabel
        items[idx].value = value
        items[idx].accent = accent
        guard save() else {
            items[idx] = previous
            return false
        }
        return true
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        guard !isStorageBlocked,
              let idx = items.firstIndex(where: { $0.id == id }) else { return false }
        let removed = items.remove(at: idx)
        let saved = save()
        if !saved { hasUnsavedChanges = true }

        lastDeleted = (removed, idx)
        undoTimer?.invalidate()
        undoTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.lastDeleted = nil
            }
        }
        return saved
    }

    @discardableResult
    func undoDelete() -> Bool {
        guard let deleted = lastDeleted, !isStorageBlocked, !isFull else {
            lastDeleted = nil
            return false
        }
        let insertIndex = min(deleted.index, items.count)
        items.insert(deleted.item, at: insertIndex)
        lastDeleted = nil
        undoTimer?.invalidate()
        let saved = save()
        if !saved { hasUnsavedChanges = true }
        return saved
    }

    @discardableResult
    func move(fromID: UUID, toID: UUID) -> Bool {
        guard !isStorageBlocked,
              fromID != toID,
              let fromIndex = items.firstIndex(where: { $0.id == fromID }),
              let toIndex = items.firstIndex(where: { $0.id == toID }) else { return false }
        let moved = items.remove(at: fromIndex)
        items.insert(moved, at: toIndex)
        let saved = save()
        if !saved { hasUnsavedChanges = true }
        return saved
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

    /// Returns how many pins were accepted and whether they were persisted.
    /// `added > 0 && !saved` means the pins exist in memory only (retry from the footer).
    func importJSON(_ data: Data) -> (added: Int, saved: Bool) {
        guard !isStorageBlocked else { return (0, false) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let imported = try? decoder.decode([PinItem].self, from: data) else { return (0, false) }
        var existingValues = Set(items.map { $0.value })
        var added = 0
        for item in imported {
            if isFull { break }
            // Skip blank/whitespace-only records; they can never be copied or displayed.
            guard !item.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            // Track accepted values too, so duplicate records inside one file are
            // only accepted once and do not waste slots toward the cap.
            if !existingValues.contains(item.value) {
                existingValues.insert(item.value)
                items.append(PinItem(label: item.label, value: item.value, accent: item.accent))
                added += 1
            }
        }
        guard added > 0 else { return (0, true) }
        let saved = save()
        if !saved { hasUnsavedChanges = true }
        return (added, saved)
    }

    // MARK: - Load-Failure Recovery

    /// Re-reads pins.json after a failed load; clears `loadError` on success.
    @discardableResult
    func retryLoad() -> Bool {
        guard isStorageBlocked else { return true }
        load()
        return !isStorageBlocked
    }

    /// Copies the unreadable pins.json to a timestamped backup beside it, then
    /// unblocks storage so normal saves can start from an empty shelf. The
    /// original data is never lost: `loadError` only clears if the backup
    /// succeeded, and the original file is only removed after the copy is safe.
    @discardableResult
    func backupAndResetStorage() -> Bool {
        guard isStorageBlocked else { return true }
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            // Nothing left to preserve (removed externally); just unblock.
            loadError = nil
            return true
        }
        let timestamp = Int(Date.now.timeIntervalSince1970)
        let suffix = UUID().uuidString.prefix(6).lowercased()
        let backupURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("pins.backup-\(timestamp)-\(suffix).json")
        do {
            try FileManager.default.copyItem(at: storageURL, to: backupURL)
        } catch {
            // Backup failed: keep the original untouched and stay blocked.
            loadError = "Backup failed — original pins.json was left untouched."
            return false
        }
        do {
            try FileManager.default.removeItem(at: storageURL)
        } catch {
            // Preserve the completed backup and keep storage blocked until the old file is removed.
            loadError = "Backup saved, but old pins.json could not be removed."
            return false
        }
        loadError = nil
        saveError = nil
        hasUnsavedChanges = false
        return true
    }

    /// Clears transient save error text when no unsaved in-memory mutations remain.
    func clearTransientSaveError() {
        if !hasUnsavedChanges {
            saveError = nil
        }
    }

    /// Persists the current in-memory items again after a failed save.
    @discardableResult
    func retrySave() -> Bool {
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            // No file yet is a normal first run, not an error; saves are permitted.
            items = []
            loadError = nil
            return
        }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([PinItem].self, from: data)
            items = Array(decoded.prefix(Self.maxItems))
            loadError = nil
            saveError = nil
            hasUnsavedChanges = false
        } catch {
            // The file exists but is unreadable or corrupted. Keep items empty and
            // refuse to overwrite it so Retry / Back Up & Reset can recover it.
            items = []
            loadError = "Could not read saved pins. Original file preserved."
        }
    }

    @discardableResult
    private func save() -> Bool {
        // Never overwrite pins.json while its existing contents could not be read.
        guard !isStorageBlocked else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Array(items.prefix(Self.maxItems)))
            try data.write(to: storageURL, options: [.atomic])
            saveError = nil
            hasUnsavedChanges = false
            return true
        } catch {
            // Surface the failure: callers keep the change in memory (or revert it)
            // and the Whisper footer offers a Retry until a save succeeds.
            saveError = "Couldn't save pins."
            return false
        }
    }
}
