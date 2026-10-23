import AppKit
import ApplicationServices
import Observation

/// One CGEventTap that replaces the Karabiner rules: matches hotkeys (tap and hold), opens the emoji
/// picker on a lone fn/🌐 press and watches Caps Lock for caffeine. Anything unbound passes through
/// untouched, so fn+F-keys and the rest of the keyboard keep their normal behaviour.
@Observable
final class KeyEngine {
    static let shared = KeyEngine()
    /// Marks events we synthesize ourselves (emoji typing) so the tap ignores them.
    static let syntheticMarker: Int64 = 0xC0_01_70_01

    private(set) var isRunning = false
    /// Last key seen, for the key tester in Settings.
    private(set) var lastKey = ""

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var recorder: ((KeyCombo) -> Void)?
    @ObservationIgnored private var swallowed = Set<UInt16>()
    @ObservationIgnored private var holding: (key: UInt16, hotkey: Hotkey, timer: DispatchWorkItem, fired: Bool)?
    @ObservationIgnored private var fnArmedAt: Date?
    @ObservationIgnored private var capsLock = false

    private var settings: AppSettings { .shared }

    // MARK: Lifecycle

    /// Starts the tap once Accessibility is granted, polling until it is.
    func start(prompt: Bool) {
        if prompt {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        guard !isRunning else { return }
        guard AXIsProcessTrusted(), installTap() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start(prompt: false) }
            return
        }
        isRunning = true
        capsLock = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        Caffeine.shared.capsLockChanged(capsLock, announce: false)
    }

    private func installTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14 /* NX_SYSDEFINED */)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            KeyEngine.shared.handle(type, event)
        }
        for location in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            if let tap = CGEvent.tapCreate(tap: location, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: nil) {
                let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                self.tap = tap
                return true
            }
        }
        return false
    }

    /// Captures the next key press (used by the shortcut recorder). Pass nil to cancel.
    func record(_ handler: ((KeyCombo) -> Void)?) { recorder = handler }

    // MARK: Event handling

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case _ where event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker:
            return pass
        case .flagsChanged:
            handleFlags(event)
            return pass
        case .keyDown, .keyUp:
            fnArmedAt = nil
            let raw = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let key = KeyNames.mediaKeyCodes[raw] ?? raw
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let swallow = handleKey(key, KeyCombo.Modifiers(event.flags), down: type == .keyDown,
                                    isRepeat: isRepeat, source: "keycode \(raw)")
            return swallow ? nil : pass
        case CGEventType(rawValue: 14):
            guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else { return pass }
            let aux = (ns.data1 & 0xFFFF_0000) >> 16
            let state = (ns.data1 & 0xFF00) >> 8
            guard let key = KeyNames.auxKeys[aux], state == 0xA || state == 0xB else { return pass }
            fnArmedAt = nil
            let swallow = handleKey(key, KeyCombo.Modifiers(event.flags), down: state == 0xA,
                                    isRepeat: ns.data1 & 1 != 0, source: "media key \(aux)")
            return swallow ? nil : pass
        default:
            return pass
        }
    }

    private func handleFlags(_ event: CGEvent) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        if code == 63 || code == 179 { // fn / 🌐
            if flags.contains(.maskSecondaryFn) {
                fnArmedAt = Date()
            } else if let armed = fnArmedAt {
                fnArmedAt = nil
                if Date().timeIntervalSince(armed) < 0.8, settings.emojiPickerEnabled {
                    DispatchQueue.main.async { EmojiPicker.shared.toggle() }
                }
            }
        } else {
            fnArmedAt = nil
        }
        let caps = flags.contains(.maskAlphaShift)
        if caps != capsLock {
            capsLock = caps
            DispatchQueue.main.async { Caffeine.shared.capsLockChanged(caps, announce: true) }
        }
    }

    /// Returns true when the event should be swallowed.
    private func handleKey(_ key: UInt16, _ mods: KeyCombo.Modifiers, down: Bool, isRepeat: Bool, source: String) -> Bool {
        let combo = KeyCombo(keyCode: key, modifiers: mods)
        if down, !isRepeat { lastKey = "\(combo.display)  (\(source))" }

        if down, let recorder {
            self.recorder = nil
            swallowed.insert(key)
            DispatchQueue.main.async { recorder(combo) }
            return true
        }

        guard down else {
            guard swallowed.remove(key) != nil else { return false }
            if let h = holding, h.key == key {
                holding = nil
                h.timer.cancel()
                if !h.fired { Actions.perform(h.hotkey.action) }
            }
            return true
        }

        if holding?.key == key { return true }
        guard let hotkey = settings.hotkeys.first(where: { $0.enabled && $0.combo == combo }) else { return false }
        swallowed.insert(key)

        if hotkey.hold != .none {
            guard !isRepeat else { return true }
            let timer = DispatchWorkItem { [weak self] in
                guard let self, self.holding?.key == key else { return }
                self.holding?.fired = true
                Actions.performHold(hotkey.hold)
            }
            holding = (key, hotkey, timer, false)
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.holdDuration, execute: timer)
        } else if !isRepeat || hotkey.action.repeats {
            Actions.perform(hotkey.action)
        }
        return true
    }
}
