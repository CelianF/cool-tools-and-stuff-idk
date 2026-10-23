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
        print("backlight level:", KeyboardBacklight.shared.level.map { String($0) } ?? "unavailable")
        print("dark mode:", Appearance.isDark)
        print("lid rule installed:", Caffeine.shared.lidRuleInstalled)
        print("accessibility:", AXIsProcessTrusted())
        exit(0)
    }
}
