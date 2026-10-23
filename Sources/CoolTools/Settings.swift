import AppKit
import Observation

/// A key plus modifiers. `keyCode` is a normalized virtual keycode: media versions of the
/// top-row keys (brightness, Spotlight, DND…) are folded onto their F-key so a shortcut works
/// whatever "Use F1, F2, etc. as standard function keys" is set to.
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: Modifiers

    struct Modifiers: OptionSet, Codable, Hashable {
        let rawValue: Int
        static let command = Modifiers(rawValue: 1 << 0)
        static let control = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)

        init(rawValue: Int) { self.rawValue = rawValue }
        init(_ flags: CGEventFlags) {
            var m: Modifiers = []
            if flags.contains(.maskCommand) { m.insert(.command) }
            if flags.contains(.maskControl) { m.insert(.control) }
            if flags.contains(.maskAlternate) { m.insert(.option) }
            if flags.contains(.maskShift) { m.insert(.shift) }
            self = m
        }

        var symbols: String {
            (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "") +
            (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
        }
    }

    var display: String { modifiers.symbols + KeyNames.name(for: keyCode) }
}

enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case backlightDown, backlightUp, darkMode, lightMode, doNotDisturb, appSwitcher
    var id: String { rawValue }

    var title: String {
        switch self {
        case .backlightDown: "Keyboard brightness down"
        case .backlightUp: "Keyboard brightness up"
        case .darkMode: "Dark mode"
        case .lightMode: "Light mode"
        case .doNotDisturb: "Toggle Do Not Disturb"
        case .appSwitcher: "App switcher (⌘⇥)"
        }
    }

    var symbol: String {
        switch self {
        case .backlightDown: "light.min"
        case .backlightUp: "light.max"
        case .darkMode: "moon.fill"
        case .lightMode: "sun.max.fill"
        case .doNotDisturb: "moon.zzz.fill"
        case .appSwitcher: "square.on.square"
        }
    }

    /// Whether holding the key should auto-repeat the action (only when no hold action is set).
    var repeats: Bool { self == .backlightDown || self == .backlightUp }

    /// The app switcher acts while the key is held, so it can't also have a hold action.
    var supportsHold: Bool { self != .appSwitcher }
}

enum HoldAction: String, Codable, CaseIterable, Identifiable {
    case none, sleepFocus, sleepMac, lockScreen, toggleCaffeine
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Nothing"
        case .sleepFocus: "Toggle Sleep Focus"
        case .sleepMac: "Put Mac to sleep"
        case .lockScreen: "Lock screen"
        case .toggleCaffeine: "Toggle caffeine"
        }
    }
}

struct Hotkey: Codable, Identifiable, Hashable {
    var action: HotkeyAction
    var combo: KeyCombo?
    var enabled = true
    var hold: HoldAction = .none
    var id: HotkeyAction { action }

    static let defaults: [Hotkey] = [
        Hotkey(action: .backlightDown, combo: KeyCombo(keyCode: KeyNames.f1, modifiers: .command)),
        Hotkey(action: .backlightUp, combo: KeyCombo(keyCode: KeyNames.f2, modifiers: .command)),
        Hotkey(action: .darkMode, combo: KeyCombo(keyCode: KeyNames.f1, modifiers: .control)),
        Hotkey(action: .lightMode, combo: KeyCombo(keyCode: KeyNames.f2, modifiers: .control)),
        Hotkey(action: .doNotDisturb, combo: KeyCombo(keyCode: KeyNames.f6, modifiers: []), hold: .sleepFocus),
        Hotkey(action: .appSwitcher, combo: KeyCombo(keyCode: KeyNames.f3, modifiers: [])),
    ]
}

enum EmojiLanguage: String, CaseIterable, Identifiable {
    case auto, english, french
    var id: String { rawValue }
    var title: String { switch self { case .auto: "System"; case .english: "English"; case .french: "Français" } }
    var isFrench: Bool {
        switch self {
        case .auto: Locale.preferredLanguages.first?.hasPrefix("fr") ?? false
        case .english: false
        case .french: true
        }
    }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let store = UserDefaults.standard

    var hotkeys: [Hotkey] { didSet { save(hotkeys, "hotkeys") } }
    var holdDuration: Double { didSet { store.set(holdDuration, forKey: "holdDuration") } }
    var showHUD: Bool { didSet { store.set(showHUD, forKey: "showHUD") } }
    var showMenuBarIcon: Bool { didSet { store.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }

    var emojiPickerEnabled: Bool { didSet { store.set(emojiPickerEnabled, forKey: "emojiPickerEnabled") } }
    var emojiLanguage: EmojiLanguage { didSet { store.set(emojiLanguage.rawValue, forKey: "emojiLanguage") } }
    /// 0 = default yellow, 1…5 = light → dark.
    var skinTone: Int { didSet { store.set(skinTone, forKey: "skinTone") } }
    var recentEmoji: [String] { didSet { store.set(recentEmoji, forKey: "recentEmoji") } }

    var capsLockCaffeine: Bool { didSet { store.set(capsLockCaffeine, forKey: "capsLockCaffeine") } }
    var caffeineKeepsDisplayOn: Bool { didSet { store.set(caffeineKeepsDisplayOn, forKey: "caffeineKeepsDisplayOn") } }
    var caffeineLidDisplayOff: Bool { didSet { store.set(caffeineLidDisplayOff, forKey: "caffeineLidDisplayOff") } }
    var caffeineLidClosed: Bool { didSet { store.set(caffeineLidClosed, forKey: "caffeineLidClosed") } }
    var caffeineBatteryFloor: Int { didSet { store.set(caffeineBatteryFloor, forKey: "caffeineBatteryFloor") } }

    private init() {
        store.register(defaults: [
            "holdDuration": 0.5, "showHUD": true, "showMenuBarIcon": true,
            "emojiPickerEnabled": true, "emojiLanguage": EmojiLanguage.auto.rawValue, "skinTone": 0,
            "capsLockCaffeine": true, "caffeineKeepsDisplayOn": false, "caffeineLidDisplayOff": true, "caffeineLidClosed": true,
            "caffeineBatteryFloor": 15,
        ])
        var hotkeys = (store.data(forKey: "hotkeys")).flatMap { try? JSONDecoder().decode([Hotkey].self, from: $0) } ?? []
        if hotkeys.count != Hotkey.defaults.count { hotkeys = Hotkey.defaults }
        self.hotkeys = hotkeys.sorted { a, b in
            HotkeyAction.allCases.firstIndex(of: a.action)! < HotkeyAction.allCases.firstIndex(of: b.action)!
        }
        holdDuration = store.double(forKey: "holdDuration")
        showHUD = store.bool(forKey: "showHUD")
        showMenuBarIcon = store.bool(forKey: "showMenuBarIcon")
        emojiPickerEnabled = store.bool(forKey: "emojiPickerEnabled")
        emojiLanguage = EmojiLanguage(rawValue: store.string(forKey: "emojiLanguage") ?? "") ?? .auto
        skinTone = store.integer(forKey: "skinTone")
        recentEmoji = store.stringArray(forKey: "recentEmoji") ?? []
        capsLockCaffeine = store.bool(forKey: "capsLockCaffeine")
        caffeineKeepsDisplayOn = store.bool(forKey: "caffeineKeepsDisplayOn")
        caffeineLidDisplayOff = store.bool(forKey: "caffeineLidDisplayOff")
        caffeineLidClosed = store.bool(forKey: "caffeineLidClosed")
        caffeineBatteryFloor = store.integer(forKey: "caffeineBatteryFloor")
    }

    func resetHotkeys() { hotkeys = Hotkey.defaults }

    func noteRecent(_ emoji: String) {
        recentEmoji = Array(([emoji] + recentEmoji.filter { $0 != emoji }).prefix(27))
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        store.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
