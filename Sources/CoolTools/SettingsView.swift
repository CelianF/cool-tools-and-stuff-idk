import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralPane() }
            Tab("Shortcuts", systemImage: "keyboard") { ShortcutsPane() }
            Tab("Emoji", systemImage: "face.smiling") { EmojiPane() }
            Tab("Focus", systemImage: "moon") { FocusPane() }
            Tab("Caffeine", systemImage: "cup.and.saucer") { CaffeinePane() }
        }
        .frame(width: 560, height: 520)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Bindable private var settings = AppSettings.shared
    private let engine = KeyEngine.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let karabinerRunning = NSWorkspace.shared.runningApplications
        .contains { $0.bundleIdentifier?.hasPrefix("org.pqrs") == true }

    var body: some View {
        Form {
            Section("Permissions") {
                LabeledContent("Accessibility") {
                    if engine.isRunning {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") {
                            KeyEngine.shared.start(prompt: true)
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                if !engine.isRunning {
                    Text("Cool Tools needs Accessibility access to see the keyboard. Turn it on in System Settings → Privacy & Security → Accessibility; it starts working right away.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if karabinerRunning {
                Section {
                    Label("Karabiner-Elements is running. Its F1/F2 rules will fight with Cool Tools — remove them or quit Karabiner (Cool Tools replaces it).",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            Section("App") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                Toggle("Show on-screen feedback", isOn: $settings.showHUD)
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                if !settings.showMenuBarIcon {
                    Text("Open Cool Tools again from Applications to get back here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Key tester") {
                LabeledContent("Last key", value: engine.lastKey.isEmpty ? "Press any key…" : engine.lastKey)
                    .monospacedDigit()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                ForEach($settings.hotkeys) { $hotkey in
                    HStack {
                        Toggle(isOn: $hotkey.enabled) {
                            Label(hotkey.action.title, systemImage: hotkey.action.symbol)
                        }
                        .toggleStyle(.checkbox)
                        Spacer()
                        Picker("Hold", selection: $hotkey.hold) {
                            ForEach(HoldAction.allCases) { Text($0 == .none ? "—" : "Hold: \($0.title)").tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        ShortcutRecorder(combo: $hotkey.combo)
                    }
                    .disabled(!hotkey.enabled && false)
                }
            } header: {
                Text("Hotkeys")
            } footer: {
                Text("Top-row keys match whether they're in media or F-key mode, so fn+F-keys still do their usual thing. Click a shortcut, then press the new keys (⌫ clears, ⎋ cancels).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Hold delay") {
                    HStack {
                        Slider(value: $settings.holdDuration, in: 0.25...1.5, step: 0.05)
                        Text("\(settings.holdDuration, specifier: "%.2f") s").monospacedDigit().frame(width: 52)
                    }
                }
                Button("Restore Defaults") { settings.resetHotkeys() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false

    var body: some View {
        Button {
            recording.toggle()
            KeyEngine.shared.record(recording ? { new in
                recording = false
                switch (Int(new.keyCode), new.modifiers.isEmpty) {
                case (kVK_Escape, true): break
                case (kVK_Delete, true): combo = nil
                default: combo = new
                }
            } : nil)
        } label: {
            Text(recording ? "Press keys…" : combo?.display ?? "Not set")
                .monospaced()
                .frame(minWidth: 86)
        }
        .tint(recording ? .accentColor : nil)
        .buttonStyle(.bordered)
        .disabled(!KeyEngine.shared.isRunning)
    }
}

// MARK: - Emoji

private struct EmojiPane: View {
    @Bindable private var settings = AppSettings.shared
    @State private var globeUsage = Self.readGlobeUsage()
    private let store = EmojiStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Open emoji picker with fn / 🌐", isOn: $settings.emojiPickerEnabled)
                if settings.emojiPickerEnabled && globeUsage != 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("macOS also reacts to the 🌐 key. Set “Press 🌐 key to” → “Do Nothing” so only Cool Tools' picker opens.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Open Keyboard Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                        }
                    }
                }
                Button("Open Picker Now") { EmojiPicker.shared.open() }
            } footer: {
                Text("\(store.all.count) emoji indexed with English and French names. Arrows to move, ↩ to insert, ⇧↩ or ⇧-click to keep it open, right-click for skin tones.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Options") {
                Picker("Names", selection: $settings.emojiLanguage) {
                    ForEach(EmojiLanguage.allCases) { Text($0.title).tag($0) }
                }
                Picker("Default skin tone", selection: $settings.skinTone) {
                    ForEach(0..<6) { i in
                        Text(["👋", "👋🏻", "👋🏼", "👋🏽", "👋🏾", "👋🏿"][i]).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                Button("Clear Recently Used") { settings.recentEmoji = [] }
                    .disabled(settings.recentEmoji.isEmpty)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            globeUsage = Self.readGlobeUsage()
        }
    }

    /// 0 = Do Nothing, 1 = Change Input Source, 2 = Show Emoji & Symbols, 3 = Start Dictation.
    private static func readGlobeUsage() -> Int {
        CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
        return (CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString) as? Int) ?? 1
    }
}

// MARK: - Focus

private struct FocusPane: View {
    @Bindable private var settings = AppSettings.shared
    @State private var installed: [String] = []

    var body: some View {
        Form {
            Section {
                shortcutRow("Do Not Disturb", $settings.dndShortcut, helper: Focus.helperShortcuts[0])
                shortcutRow("Sleep Focus", $settings.sleepFocusShortcut, helper: Focus.helperShortcuts[1])
            } header: {
                Text("Shortcuts used to toggle Focus")
            } footer: {
                Text("macOS only lets other apps change Focus through the Shortcuts app. Click Install to add the ready-made helper shortcuts (Shortcuts asks you to confirm), or pick one of your own.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Refresh") { Task { installed = await Focus.installedShortcuts() } }
            }
        }
        .formStyle(.grouped)
        .task { installed = await Focus.installedShortcuts() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { installed = await Focus.installedShortcuts() }
        }
    }

    private func shortcutRow(_ title: String, _ name: Binding<String>, helper: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if installed.contains(name.wrappedValue) {
                    Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Test") { Focus.run(name.wrappedValue, title: title, symbol: "moon.fill") }
                } else {
                    Label("Not found", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            HStack {
                Picker("Shortcut", selection: name) {
                    if !installed.contains(name.wrappedValue) { Text(name.wrappedValue).tag(name.wrappedValue) }
                    ForEach(installed, id: \.self) { Text($0).tag($0) }
                }
                if !installed.contains(helper) {
                    Button("Install") {
                        name.wrappedValue = helper
                        Focus.install(helper)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Caffeine

private struct CaffeinePane: View {
    @Bindable private var settings = AppSettings.shared
    @Bindable private var caffeine = Caffeine.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Label(caffeine.isActive ? "Awake" : "Off",
                          systemImage: caffeine.isActive ? "cup.and.heat.waves.fill" : "cup.and.saucer")
                        .foregroundStyle(caffeine.isActive ? .orange : .secondary)
                }
                Toggle("Caffeinate while Caps Lock is on", isOn: $settings.capsLockCaffeine)
                    .onChange(of: settings.capsLockCaffeine) { caffeine.update(announce: true) }
                Toggle("Caffeinate now (manual)", isOn: $caffeine.manual)
                Toggle("Keep the display on too", isOn: $settings.caffeineKeepsDisplayOn)
                    .onChange(of: settings.caffeineKeepsDisplayOn) { caffeine.update() }
            }
            Section {
                Toggle("Stay awake with the lid closed", isOn: $settings.caffeineLidClosed)
                    .onChange(of: settings.caffeineLidClosed) { caffeine.update() }
                LabeledContent("Lid-closed helper") {
                    if caffeine.lidRuleInstalled {
                        HStack {
                            Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Button("Remove") { caffeine.removeLidRule() }
                        }
                    } else {
                        Button("Set Up…") { caffeine.installLidRule() }
                    }
                }
            } footer: {
                Text("Closing the lid always sleeps a Mac unless sleep is disabled with `pmset disablesleep`, which needs admin rights. Set Up asks for your password once and adds a sudoers rule that only allows that one command. It's switched back off as soon as caffeine stops.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Stepper("Turn off below \(settings.caffeineBatteryFloor)% battery",
                        value: $settings.caffeineBatteryFloor, in: 0...50, step: 5)
            } footer: {
                Text("A closed MacBook that never sleeps can get hot in a bag — this is the safety net.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
