import AppKit
import SwiftUI

/// Borderless, keyable floating NSPanel tailored for Whisper Compact.
final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@main
@MainActor
final class ShelfAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: ShelfPanel!
    private var hostingController: NSHostingController<ShelfPopoverView>!

    private let store = ShelfStore()
    private let ui = ShelfUIState()
    private let hotKeyManager = HotKeyManager()
    private let launchAtLogin = LaunchAtLoginManager()

    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var iconResetTimer: Timer?
    private var dismissTimer: Timer?
    private var currentHeight: CGFloat = 200
    private let panelWidth: CGFloat = 272

    static func main() {
        let app = NSApplication.shared
        let delegate = ShelfAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // Menu bar only, no Dock icon
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        setupPanel()
        setupHotKey()
        setupStoreFeedback()
    }

    func applicationDidResignActive(_ notification: Notification) {
        if panel.isVisible && NSApp.modalWindow == nil {
            closePanel()
        }
    }

    /// Provides standard Edit actions so ⌘V, ⌘C, ⌘X, ⌘A work inside inline TextFields.
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status Bar Icon

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        setStatusIcon(copied: false)
        button.action = #selector(handleStatusBarClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Shelf — Your top 20 go-to links & snippets"
    }

    private func setStatusIcon(copied: Bool) {
        guard let button = statusItem.button else { return }
        if copied {
            let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .semibold)
            let img = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copied")?
                .withSymbolConfiguration(config)
            img?.isTemplate = true
            button.image = img
        } else {
            let config = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .medium)
            let img = NSImage(systemSymbolName: "books.vertical.fill", accessibilityDescription: "Shelf")?
                .withSymbolConfiguration(config)
            img?.isTemplate = true
            button.image = img
        }
    }

    @objc private func handleStatusBarClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePanel()
            return
        }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Shelf", action: #selector(menuOpenShelf), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let newItem = NSMenuItem(title: "Add to Shelf…", action: #selector(menuNewPin), keyEquivalent: "")
        newItem.target = self
        newItem.isEnabled = !store.isFull && !store.isStorageBlocked
        menu.addItem(newItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Shelf", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuOpenShelf() {
        openPanel(openComposer: false)
    }

    @objc private func menuNewPin() {
        openPanel(openComposer: true)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - Floating Whisper Panel

    private func setupPanel() {
        let rootView = ShelfPopoverView(
            store: store,
            ui: ui,
            hotKeyManager: hotKeyManager,
            launchAtLogin: launchAtLogin,
            onCopyAndDismiss: { [weak self] item in
                self?.copyAndDismiss(item)
            },
            onOpenURLAndDismiss: { [weak self] item in
                self?.store.openURL(for: item)
                self?.closePanel()
            },
            onQuit: {
                NSApp.terminate(nil)
            },
            onHeightChange: { [weak self] newHeight in
                self?.updatePanelHeight(newHeight)
            }
        )

        hostingController = NSHostingController(rootView: rootView)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        panel = ShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: currentHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.contentViewController = hostingController
    }

    private func setupHotKey() {
        hotKeyManager.onTrigger = { [weak self] in
            self?.togglePanel()
        }
    }

    private func setupStoreFeedback() {
        store.onCopiedFeedback = { [weak self] in
            guard let self else { return }
            self.setStatusIcon(copied: true)
            self.iconResetTimer?.invalidate()
            self.iconResetTimer = Timer.scheduledTimer(withTimeInterval: 1.15, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.setStatusIcon(copied: false)
                }
            }
        }
    }

    // MARK: - Open / Close / Position

    private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            openPanel(openComposer: false)
        }
    }

    private func openPanel(openComposer: Bool) {
        dismissTimer?.invalidate()
        ui.resetForOpen(openComposer: openComposer)
        launchAtLogin.refresh()

        positionPanel(height: currentHeight)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        startEventMonitors()
    }

    private func closePanel() {
        dismissTimer?.invalidate()
        stopEventMonitors()
        panel.orderOut(nil)
    }

    private func copyAndDismiss(_ item: PinItem) {
        store.copy(item)
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 0.24, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.closePanel()
            }
        }
    }

    private func updatePanelHeight(_ newHeight: CGFloat) {
        let clamped = max(100, min(ceil(newHeight), 520))
        guard abs(clamped - currentHeight) > 0.5 else { return }
        currentHeight = clamped
        if panel.isVisible {
            positionPanel(height: clamped)
        }
    }

    private func positionPanel(height: CGFloat) {
        guard let button = statusItem.button,
              let buttonWindow = button.window else {
            return
        }
        let buttonFrame = buttonWindow.frame
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Right-aligned gently under the status icon, clamped safely inside screen bounds
        var originX = buttonFrame.midX - (panelWidth / 2)
        let margin: CGFloat = 10
        if originX + panelWidth > visibleFrame.maxX - margin {
            originX = visibleFrame.maxX - panelWidth - margin
        }
        if originX < visibleFrame.minX + margin {
            originX = visibleFrame.minX + margin
        }

        let topY = buttonFrame.minY - 6
        let originY = topY - height

        panel.setFrame(
            NSRect(x: round(originX), y: round(originY), width: panelWidth, height: height),
            display: true
        )
    }

    // MARK: - Event Monitors (Click Outside + Keyboard Navigation + Type-to-Filter)

    private func startEventMonitors() {
        stopEventMonitors()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.isVisible, NSApp.modalWindow == nil else { return }
                self.closePanel()
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func stopEventMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Escape always cascades cleanly: close composer/settings -> clear filter -> close panel
        if event.keyCode == 53 {
            if ui.composerMode != nil {
                store.clearTransientSaveError()
                withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                    ui.composerMode = nil
                }
                return nil
            }
            if ui.showSettings {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                    ui.showSettings = false
                }
                return nil
            }
            if !ui.filterText.isEmpty {
                withAnimation(.easeOut(duration: 0.14)) {
                    ui.filterText = ""
                    ui.selectedIndex = nil
                }
                return nil
            }
            closePanel()
            return nil
        }

        // If typing inside the inline composer, let TextField handle all regular input!
        if ui.composerMode != nil {
            return event
        }

        // Global panel command shortcuts
        if flags.contains(.command) {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                // ⌘Q: Quit
                if chars == "q" {
                    NSApp.terminate(nil)
                    return nil
                }
                // ⌘N: Add to Shelf
                if chars == "n" {
                    if !store.isFull && !store.isStorageBlocked {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                            ui.showSettings = false
                            ui.composerMode = .add(prefill: nil)
                        }
                    }
                    return nil
                }
                // ⌘,: Preferences
                if chars == "," {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                        ui.composerMode = nil
                        ui.showSettings.toggle()
                    }
                    return nil
                }
                // ⌘Z: Undo Delete
                if chars == "z", store.lastDeleted != nil {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                        _ = store.undoDelete()
                    }
                    return nil
                }
                // ⌘1...⌘9: Instant Copy
                if let digit = Int(chars), (1...9).contains(digit) {
                    let visible = ui.filteredItems(from: store.items)
                    if visible.indices.contains(digit - 1) {
                        copyAndDismiss(visible[digit - 1])
                    }
                    return nil
                }
            }
            return event
        }

        if ui.showSettings {
            return event
        }

        let visible = ui.filteredItems(from: store.items)

        // Down arrow
        if event.keyCode == 125 {
            guard !visible.isEmpty else { return nil }
            if let current = ui.selectedIndex {
                ui.selectedIndex = (current + 1) % visible.count
            } else {
                ui.selectedIndex = 0
            }
            return nil
        }

        // Up arrow
        if event.keyCode == 126 {
            guard !visible.isEmpty else { return nil }
            if let current = ui.selectedIndex {
                ui.selectedIndex = (current - 1 + visible.count) % visible.count
            } else {
                ui.selectedIndex = visible.count - 1
            }
            return nil
        }

        // Return / Enter -> Copy selected or first visible pin
        if event.keyCode == 36 || event.keyCode == 76 {
            guard !visible.isEmpty else { return nil }
            let targetIndex = ui.selectedIndex.flatMap { visible.indices.contains($0) ? $0 : nil } ?? 0
            copyAndDismiss(visible[targetIndex])
            return nil
        }

        // Backspace -> delete from live type-to-filter query
        if event.keyCode == 51 {
            if !ui.filterText.isEmpty {
                ui.filterText.removeLast()
                let updated = ui.filteredItems(from: store.items)
                ui.selectedIndex = ui.filterText.isEmpty ? nil : (updated.isEmpty ? nil : 0)
            }
            return nil
        }

        // Any printable character (no Control/Command/Option) -> live type-to-filter!
        if flags.isDisjoint(with: [.control, .option, .command]),
           let chars = event.characters,
           chars.count == 1,
           let scalar = chars.unicodeScalars.first,
           CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols).union(.whitespaces).contains(scalar),
           !CharacterSet.newlines.contains(scalar) {
            if ui.filterText.isEmpty && chars == " " {
                return nil
            }
            ui.filterText.append(chars)
            let updated = ui.filteredItems(from: store.items)
            ui.selectedIndex = updated.isEmpty ? nil : 0
            return nil
        }

        return event
    }
}
