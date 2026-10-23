import AppKit

enum Actions {
    static func perform(_ action: HotkeyAction) {
        switch action {
        case .backlightDown: KeyboardBacklight.step(by: -1)
        case .backlightUp: KeyboardBacklight.step(by: 1)
        case .darkMode: Appearance.set(dark: true)
        case .lightMode: Appearance.set(dark: false)
        case .doNotDisturb: DoNotDisturb.toggle()
        }
    }

    static func performHold(_ action: HoldAction) {
        switch action {
        case .none: break
        case .sleepFocus: FocusMode.toggleSleep()
        case .sleepMac:
            HUD.show(symbol: "powersleep", title: "Sleeping…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Shell.run("/usr/bin/pmset", ["sleepnow"]) }
        case .lockScreen:
            SystemLock.lock()
        case .toggleCaffeine:
            Caffeine.shared.toggleManual()
        }
    }
}

// MARK: - Keyboard backlight

/// Sends the system's own illumination keys, so macOS changes the backlight and shows its native HUD.
enum KeyboardBacklight {
    static func step(by direction: Int) { MediaKey.post(direction > 0 ? 21 : 22) } // NX_KEYTYPE_ILLUMINATION_UP / DOWN
}

enum MediaKey {
    static func post(_ key: Int32) {
        for down in [true, false] {
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                           modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                           data1: data1, data2: -1)
            let cg = event?.cgEvent
            cg?.setIntegerValueField(.eventSourceUserData, value: KeyEngine.syntheticMarker)
            cg?.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Appearance

enum Appearance {
    private typealias SetTheme = @convention(c) (Bool) -> Void
    private static let setTheme: SetTheme? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let sym = dlsym(handle, "SLSSetAppearanceThemeLegacy") else { return nil }
        return unsafeBitCast(sym, to: SetTheme.self)
    }()

    static var isDark: Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String
        return style == "Dark"
    }

    static func set(dark: Bool) {
        HUD.show(symbol: dark ? "moon.fill" : "sun.max.fill", title: dark ? "Dark Mode" : "Light Mode")
        guard isDark != dark else { return }
        setTheme?(dark)
        // Fall back to System Events if the private call is gone or didn't stick.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard isDark != dark else { return }
            let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"
            DispatchQueue.global().async { NSAppleScript(source: script)?.executeAndReturnError(nil) }
        }
    }
}

// MARK: - Do Not Disturb

/// Toggles Do Not Disturb through macOS' own "Turn Do Not Disturb On/Off" keyboard shortcut
/// (symbolic hotkey 175). Third-party apps can't call the Focus service directly, but WindowServer
/// handles that shortcut like any other system shortcut. If it isn't assigned yet we give it an
/// out-of-the-way combo (⌃⌥⇧⌘F19) and post that.
enum DoNotDisturb {
    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let key = "AppleSymbolicHotKeys" as CFString
    private static let id = "175"
    private static let defaultKeyCode = 80 // F19
    private static let defaultMods = 0x020000 | 0x040000 | 0x080000 | 0x100000 | 0x800000 // ⇧⌃⌥⌘ fn

    /// No HUD here: macOS shows its own Focus banner.
    static func toggle() {
        guard let (keyCode, mods) = ensureHotkey() else {
            HUD.show(symbol: "exclamationmark.triangle.fill", title: "Do Not Disturb unavailable")
            return
        }
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down) else { continue }
            e.flags = CGEventFlags(rawValue: UInt64(mods))
            e.setIntegerValueField(.eventSourceUserData, value: KeyEngine.syntheticMarker)
            e.post(tap: .cghidEventTap)
        }
    }

    /// Returns the (keycode, modifier mask) of the DND shortcut, assigning one if needed.
    @discardableResult
    static func ensureHotkey() -> (Int, Int)? {
        CFPreferencesAppSynchronize(domain)
        var all = (CFPreferencesCopyAppValue(key, domain) as? [String: Any]) ?? [:]
        if let entry = all[id] as? [String: Any], entry["enabled"] as? Bool == true,
           let value = entry["value"] as? [String: Any], let p = value["parameters"] as? [Int], p.count == 3,
           p[1] != 65535 {
            return (p[1], p[2])
        }
        all[id] = ["enabled": true,
                   "value": ["type": "standard", "parameters": [65535, defaultKeyCode, defaultMods]]] as [String: Any]
        CFPreferencesSetAppValue(key, all as CFDictionary, domain)
        CFPreferencesAppSynchronize(domain)
        // Makes WindowServer reload the shortcut table without a logout.
        Shell.run("/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings", ["-u"])
        return (defaultKeyCode, defaultMods)
    }
}

// MARK: - Lock

enum SystemLock {
    static func lock() {
        typealias Fn = @convention(c) () -> Void
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
           let sym = dlsym(handle, "SACLockScreenImmediate") {
            unsafeBitCast(sym, to: Fn.self)()
        }
    }
}

// MARK: - Shell

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    static func output(_ path: String, _ args: [String]) -> String {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
