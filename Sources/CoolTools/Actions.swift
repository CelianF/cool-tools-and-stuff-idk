import AppKit

enum Actions {
    static func perform(_ action: HotkeyAction) {
        switch action {
        case .backlightDown: KeyboardBacklight.shared.step(by: -1)
        case .backlightUp: KeyboardBacklight.shared.step(by: 1)
        case .darkMode: Appearance.set(dark: true)
        case .lightMode: Appearance.set(dark: false)
        case .doNotDisturb:
            Focus.run(AppSettings.shared.dndShortcut, title: "Do Not Disturb", symbol: "moon.fill")
        }
    }

    static func performHold(_ action: HoldAction) {
        switch action {
        case .none: break
        case .sleepFocus:
            Focus.run(AppSettings.shared.sleepFocusShortcut, title: "Sleep Focus", symbol: "bed.double.fill")
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

/// Talks to CoreBrightness' KeyboardBrightnessClient (the same thing Control Center uses).
final class KeyboardBacklight {
    static let shared = KeyboardBacklight()
    private let client: NSObject?
    private let keyboardID: UInt64

    private init() {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        let client = (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
        let ids = client?.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber]
        self.client = client
        keyboardID = ids?.first?.uint64Value ?? 1
    }

    var level: Float? {
        let sel = NSSelectorFromString("brightnessForKeyboard:")
        guard let client, client.responds(to: sel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, UInt64) -> Float
        return unsafeBitCast(client.method(for: sel), to: Fn.self)(client, sel, keyboardID)
    }

    private func set(_ value: Float) -> Bool {
        guard let client else { return false }
        let fade = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")
        if client.responds(to: fade) {
            typealias Fn = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool
            return unsafeBitCast(client.method(for: fade), to: Fn.self)(client, fade, value, 150, true, keyboardID)
        }
        let plain = NSSelectorFromString("setBrightness:forKeyboard:")
        guard client.responds(to: plain) else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        return unsafeBitCast(client.method(for: plain), to: Fn.self)(client, plain, value, keyboardID)
    }

    /// Moves in sixteenths, like the system brightness keys.
    func step(by direction: Float) {
        guard let current = level else {
            MediaKey.post(direction > 0 ? 21 : 22) // NX_KEYTYPE_ILLUMINATION_UP / DOWN fallback
            return
        }
        let next = min(1, max(0, ((current * 16).rounded() + direction) / 16))
        _ = set(next)
        HUD.show(symbol: next == 0 ? "light.min" : "light.max", title: "Keyboard", level: Double(next))
    }
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

// MARK: - Focus (via Shortcuts, the only supported way to toggle Focus modes)

enum Focus {
    static let helperShortcuts = ["Cool Tools - Toggle Do Not Disturb", "Cool Tools - Toggle Sleep Focus"]

    static func run(_ shortcut: String, title: String, symbol: String) {
        HUD.show(symbol: symbol, title: title)
        DispatchQueue.global().async {
            let status = Shell.run("/usr/bin/shortcuts", ["run", shortcut])
            if status != 0 {
                DispatchQueue.main.async {
                    HUD.show(symbol: "exclamationmark.triangle.fill", title: "Shortcut “\(shortcut)” missing")
                }
            }
        }
    }

    static func installedShortcuts() async -> [String] {
        await Task.detached {
            Shell.output("/usr/bin/shortcuts", ["list"]).split(separator: "\n").map(String.init)
        }.value
    }

    /// Opens a bundled helper shortcut so Shortcuts offers to add it.
    static func install(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "shortcut", subdirectory: "Shortcuts") else { return }
        NSWorkspace.shared.open(url)
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
