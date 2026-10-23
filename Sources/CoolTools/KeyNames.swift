import AppKit
import Carbon.HIToolbox

enum KeyNames {
    static let f1 = UInt16(kVK_F1), f2 = UInt16(kVK_F2), f3 = UInt16(kVK_F3), f4 = UInt16(kVK_F4)
    static let f5 = UInt16(kVK_F5), f6 = UInt16(kVK_F6), f7 = UInt16(kVK_F7), f8 = UInt16(kVK_F8)
    static let f9 = UInt16(kVK_F9), f10 = UInt16(kVK_F10), f11 = UInt16(kVK_F11), f12 = UInt16(kVK_F12)

    /// Keycodes the Apple top row sends in media mode, folded onto their F-key.
    static let mediaKeyCodes: [UInt16: UInt16] = [
        160: f3,  // Mission Control
        131: f4,  // Launchpad (older keyboards)
        177: f4,  // Spotlight
        176: f5,  // Dictation
        178: f6,  // Do Not Disturb
        106: f6,  // F16: what Karabiner-Elements turns F6 into
    ]

    /// NX_KEYTYPE_* values carried by NSSystemDefined media-key events, folded onto their F-key.
    static let auxKeys: [Int: UInt16] = [
        3: f1, 2: f2,               // display brightness down / up
        20: f7, 18: f7,             // rewind / previous
        16: f8,                     // play
        19: f9, 17: f9,             // fast / next
        7: f10, 1: f11, 0: f12,     // mute, volume down, volume up
    ]

    private static let fixed: [UInt16: String] = [
        f1: "F1", f2: "F2", f3: "F3", f4: "F4", f5: "F5", f6: "F6",
        f7: "F7", f8: "F8", f9: "F9", f10: "F10", f11: "F11", f12: "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16", UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18", UInt16(kVK_F19): "F19",
        UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥", UInt16(kVK_Space): "Space",
        UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→", UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓", UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟",
    ]

    static func name(for keyCode: UInt16) -> String {
        if let name = fixed[keyCode] { return name }
        return translate(keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    private static func translate(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw in
            UCKeyTranslate(raw.bindMemory(to: UCKeyboardLayout.self).baseAddress, keyCode,
                           UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
