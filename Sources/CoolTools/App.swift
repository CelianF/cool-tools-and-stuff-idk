import AppKit
import SwiftUI

@main
struct CoolToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Bindable private var settings = AppSettings.shared
    private var caffeine = Caffeine.shared

    var body: some Scene {
        MenuBarExtra(isInserted: $settings.showMenuBarIcon) {
            MenuContent()
        } label: {
            Image(systemName: caffeine.isActive ? "cup.and.heat.waves.fill" : "sparkles")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selftest") { SelfTest.run() }
        EmojiStore.shared.load()
        if AppSettings.shared.emojiPickerEnabled { GlobeKey.claim() }
        DoNotDisturb.ensureHotkey()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard AppSettings.shared.emojiPickerEnabled,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            TextFocus.wakeAccessibility(of: app)
        }
        if let front = NSWorkspace.shared.frontmostApplication { TextFocus.wakeAccessibility(of: front) }
        _ = Caffeine.shared
        let trusted = AXIsProcessTrusted()
        KeyEngine.shared.start(prompt: !trusted)
        if !trusted || !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            SettingsWindow.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Caffeine.shared.shutdown()
        GlobeKey.release()
    }
}

private struct MenuContent: View {
    @Bindable private var caffeine = Caffeine.shared
    private let settings = AppSettings.shared

    var body: some View {
        Toggle("Caffeinate", isOn: $caffeine.manual)
        if caffeine.isActive { Text(caffeine.manual ? "Awake (manual)" : "Awake (Caps Lock)") }
        Divider()
        if settings.emojiPickerEnabled {
            Button("Emoji Picker") { DispatchQueue.main.async { EmojiPicker.shared.open() } }
        }
        Button("Dark Mode") { Appearance.set(dark: true) }
        Button("Light Mode") { Appearance.set(dark: false) }
        Divider()
        Button("Settings…") { SettingsWindow.show() }.keyboardShortcut(",")
        Button("Quit Cool Tools") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Cool Tools"
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// `CoolTools --selftest` prints what the non-UI pieces see on this Mac, then quits.
enum SelfTest {
    static func run() {
        let store = EmojiStore.shared
        store.loadNow()
        print("emoji renderable:", store.all.count)
        for q in ["coeur", "heart", "chat", "pouce", "thumbs up", "drapeau france", "🎉", "visage rieur"] {
            print(q, "->", store.search(q).prefix(8).map(\.char).joined())
        }
        print("dark mode:", Appearance.isDark)
        print("lid rule installed:", Caffeine.shared.lidRuleInstalled)
        print("lid closed:", Caffeine.isLidClosed, "display asleep:", CGDisplayIsAsleep(CGMainDisplayID()) != 0)
        print("accessibility:", AXIsProcessTrusted())
        exit(0)
    }
}

/// While the picker is on, macOS' own 🌐 action is set to "Do Nothing" so the two don't both open.
/// The user's previous choice is remembered and put back when the picker is turned off or the app quits.
enum GlobeKey {
    private static let domain = "com.apple.HIToolbox" as CFString
    private static let key = "AppleFnUsageType" as CFString
    private static let savedKey = "savedGlobeUsage"

    /// 0 = Do Nothing, 1 = Change Input Source, 2 = Show Emoji & Symbols, 3 = Start Dictation.
    static var current: Int {
        CFPreferencesAppSynchronize(domain)
        return (CFPreferencesCopyAppValue(key, domain) as? Int) ?? 1
    }

    static func claim() {
        let value = current
        guard value != 0 else { return }
        UserDefaults.standard.set(value, forKey: savedKey)
        write(0)
    }

    static func release() {
        guard let saved = UserDefaults.standard.object(forKey: savedKey) as? Int else { return }
        UserDefaults.standard.removeObject(forKey: savedKey)
        write(saved)
    }

    private static func write(_ value: Int) {
        CFPreferencesSetAppValue(key, value as CFNumber, domain)
        CFPreferencesAppSynchronize(domain)
        Shell.run("/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings", ["-u"])
    }
}
