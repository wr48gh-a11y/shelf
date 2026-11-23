# Shelf

A lightweight native macOS menu bar app for your top **20 go-to links & snippets**: emails, addresses, and frequently pasted text that never get bumped down by clipboard history.

Built in **Swift & SwiftUI** with a **Whisper Compact** bookshelf design (~8 MB idle RAM, ~2.3 MB app bundle, zero Dock icon): a luminous obsidian-glass popover with vertical book-spine accents, a gentle tip-out hover tilt, a 20-spine capacity bar, and the native `books.vertical.fill` menu bar icon.

## Features

- **Fixed-Position 20-Spine Shelf:** Items stay right where you shelve them, so you build instant muscle memory.
- **Whisper Compact UI:** Ultra-slim (`272pt`) frosted-glass menu bar popover with automatic Light & Dark Mode, color-coded Whisper spines, and a quiet monospace **hover-to-peek** footer.
- **Click = Copy:** Clicking any spine copies its value, flashes a subtle green `✓` on the row and the menu bar icon, and auto-dismisses.
- **Open URLs on Demand:** Hover any URL item to click `↗`, or use `⌥+Click` to open it directly in your browser.
- **Keyboard-First Speed:**
  - `⌃⌥S`: Global hotkey to open/close Shelf from anywhere (customizable to `⌥⇧S`, `⌃⇧V`, or `Off` in Preferences)
  - `⌘1`–`⌘9`: Instant copy spines 1–9
  - `↑` / `↓` + `↩`: Navigate and copy
  - **Type to filter**: Hidden by default; start typing while Shelf is open to filter live (`Esc` clears)
  - `⌘N`: Inline **Add to Shelf** composer (with one-click **Paste from Clipboard** + smart label suggestion)
  - `⌘Z`: Undo recent delete (4.5s undo window)
  - `⌘,`: Inline Preferences (Shortcut, Launch at Login, JSON Export/Import, Quit)
- **Drag-and-Drop Reordering:** Drag spines to lock your most-used items at the top.
- **Local JSON Storage:** Stored cleanly at `~/Library/Application Support/Shelf/pins.json`.

## Requirements

- macOS 15.0+ (built and tested on macOS 26 / Apple Silicon)
- Xcode or Swift 6.0+ toolchain

## Build & Install

```bash
git clone https://github.com/wr48gh-a11y/shelf.git
cd shelf
./scripts/build-app.sh
```

This compiles the Release binary, generates the app icon, and produces an ad-hoc signed `build/Shelf.app`.

To install to Applications:

```bash
cp -R build/Shelf.app /Applications/
open /Applications/Shelf.app
```

## Project Structure

```text
Shelf/
├── Package.swift
├── scripts/
│   ├── build-app.sh                  # Release build, icon generation, .app packaging & ad-hoc signing
│   └── make-icon.swift               # Programmatic obsidian-glass bookshelf .icns icon renderer
└── Sources/Shelf/
    ├── ShelfApp.swift                # Entry point, NSStatusItem, borderless floating NSPanel, key monitors
    ├── Models/PinItem.swift          # Item model, URL/email/snippet detection, Whisper accent palette
    ├── Store/ShelfStore.swift        # Atomic JSON persistence, 20-item cap, undo delete, drag reorder
    ├── Services/
    │   ├── HotKeyManager.swift       # Carbon global hotkey (zero Accessibility permissions needed)
    │   └── LaunchAtLoginManager.swift# SMAppService Launch at Login wrapper
    └── Views/
        ├── VisualEffectView.swift    # Native macOS NSVisualEffectView frosted glass backdrop
        ├── ShelfPopoverView.swift    # Main Whisper Compact popover, live filter & peek footer
        ├── PinRowView.swift          # Book-spine Whisper row, hover micro-actions & drag delegate
        ├── PinComposerView.swift     # Inline Add to Shelf form with Paste from Clipboard
        └── SettingsDrawerView.swift  # Inline Preferences drawer (hotkey, Launch at Login, export/import)
```
