import AppKit

/// Toggles a Focus mode the way a person would: through Control Center. Apps can't call the Focus
/// service directly (it's entitlement-gated) and the only Focus keyboard shortcut is for Do Not
/// Disturb, but Control Center's Focus list is fully exposed to Accessibility.
enum FocusMode {
    /// Key in DoNotDisturb.framework's string table for the built-in Sleep mode ("Repos" in French).
    static let sleepKey = "MODE_NAME_SLEEP"

    static func toggleSleep() {
        DispatchQueue.global(qos: .userInitiated).async {
            if !toggle(named: localizedName(sleepKey, fallback: "Sleep")) {
                HUD.show(symbol: "exclamationmark.triangle.fill", title: "Sleep Focus not found")
            }
        }
    }

    /// The mode's name in the language Control Center is showing, from the system's own strings.
    static func localizedName(_ key: String, fallback: String) -> String {
        let path = "/System/Library/PrivateFrameworks/DoNotDisturb.framework/Resources/Localizable.loctable"
        guard let table = NSDictionary(contentsOfFile: path) as? [String: Any] else { return fallback }
        let lang = Bundle.preferredLocalizations(from: Array(table.keys), forPreferences: Locale.preferredLanguages).first
        func lookup(_ l: String?) -> String? { l.flatMap { (table[$0] as? [String: Any])?[key] as? String } }
        return lookup(lang) ?? lookup("en") ?? fallback
    }

    private static func toggle(named name: String) -> Bool {
        guard let agent = NSWorkspace.shared.runningApplications.first(where: { $0.executableURL?.lastPathComponent == "MenuBarAgent" }),
              let cc = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.controlcenter" }),
              let menuItem = find(AXUIElementCreateApplication(agent.processIdentifier), depth: 6, where: {
                  identifier($0) == "com.apple.menuextra.controlcenter" }) else { return false }
        let ccApp = AXUIElementCreateApplication(cc.processIdentifier)
        AXUIElementSetMessagingTimeout(ccApp, 1)

        if !isOpen(ccApp) {
            AXUIElementPerformAction(menuItem, kAXPressAction as CFString)
            guard wait({ isOpen(ccApp) }) else { return false }
        }
        // Picking a mode closes Control Center by itself; only close it if it's still up.
        defer {
            Thread.sleep(forTimeInterval: 0.3)
            if isOpen(ccApp) { AXUIElementPerformAction(menuItem, kAXPressAction as CFString) }
        }

        // Expand the Focus tile into its list of modes ("show details" is a localized custom action).
        if let tile = find(ccApp, depth: 8, where: { identifier($0).hasPrefix("controlcenter-focus-modes") }),
           let details = actions(tile).first(where: { $0.hasPrefix("Name:") }) {
            AXUIElementPerformAction(tile, details as CFString)
        }
        var toggle: AXUIElement?
        guard wait({
            toggle = find(ccApp, depth: 8, where: { role($0) == "AXCheckBox" && description($0) == name })
            return toggle != nil
        }), let toggle else { return false }
        return AXUIElementPerformAction(toggle, kAXPressAction as CFString) == .success
    }

    // MARK: AX helpers

    /// Control Center keeps its window around off-screen; it only has content while it's shown.
    private static func isOpen(_ app: AXUIElement) -> Bool { !(value(app, kAXChildrenAttribute) as [AXUIElement]? ?? []).isEmpty }

    private static func wait(_ condition: () -> Bool, timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private static func find(_ el: AXUIElement, depth: Int, where match: (AXUIElement) -> Bool) -> AXUIElement? {
        if match(el) { return el }
        guard depth > 0 else { return nil }
        for child in value(el, kAXChildrenAttribute) as [AXUIElement]? ?? [] {
            if let found = find(child, depth: depth - 1, where: match) { return found }
        }
        return nil
    }

    private static func value<T>(_ el: AXUIElement, _ attribute: String) -> T? {
        var v: AnyObject?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &v) == .success else { return nil }
        return v as? T
    }

    private static func identifier(_ el: AXUIElement) -> String { value(el, kAXIdentifierAttribute) ?? "" }
    private static func role(_ el: AXUIElement) -> String { value(el, kAXRoleAttribute) ?? "" }
    private static func description(_ el: AXUIElement) -> String { value(el, kAXDescriptionAttribute) ?? "" }

    private static func actions(_ el: AXUIElement) -> [String] {
        var names: CFArray?
        AXUIElementCopyActionNames(el, &names)
        return names as? [String] ?? []
    }
}
