import Carbon
import Foundation
import Observation

enum HotKeyPreset: String, CaseIterable, Identifiable, Sendable {
    case controlOptionS
    case optionShiftS
    case controlShiftV
    case off

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .controlOptionS: return "⌃⌥S"
        case .optionShiftS:   return "⌥⇧S"
        case .controlShiftV:  return "⌃⇧V"
        case .off:            return "Off"
        }
    }

    var description: String {
        switch self {
        case .controlOptionS: return "Control + Option + S"
        case .optionShiftS:   return "Option + Shift + S"
        case .controlShiftV:  return "Control + Shift + V"
        case .off:            return "Menu bar click only"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .controlOptionS: return UInt32(kVK_ANSI_S)
        case .optionShiftS:   return UInt32(kVK_ANSI_S)
        case .controlShiftV:  return UInt32(kVK_ANSI_V)
        case .off:            return 0
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .controlOptionS: return UInt32(controlKey | optionKey)
        case .optionShiftS:   return UInt32(optionKey | shiftKey)
        case .controlShiftV:  return UInt32(controlKey | shiftKey)
        case .off:            return 0
        }
    }
}

private let shelfHotKeySignature: OSType = 0x53484C46 // 'SHLF'

@MainActor
@Observable
final class HotKeyManager {
    private static let defaultsKey = "shelf.hotkey.preset"

    var preset: HotKeyPreset {
        didSet {
            UserDefaults.standard.set(preset.rawValue, forKey: Self.defaultsKey)
            registerCurrentPreset()
        }
    }

    var onTrigger: (() -> Void)?

    @ObservationIgnored nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey)
        self.preset = saved.flatMap(HotKeyPreset.init(rawValue:)) ?? .controlOptionS
        installEventHandler()
        registerCurrentPreset()
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let callback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == shelfHotKeySignature else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                manager.onTrigger?()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            selfPtr,
            &eventHandlerRef
        )
    }

    private func registerCurrentPreset() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        guard preset != .off else { return }

        let hotKeyID = EventHotKeyID(signature: shelfHotKeySignature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            preset.keyCode,
            preset.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            self.hotKeyRef = ref
        }
    }
}
