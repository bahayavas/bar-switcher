import AppKit
import Carbon

/// Bir global kısayol: fiziksel tuş kodu + Carbon modifier maskesi.
/// Dosyada AeroSpace biçiminde saklanır: "ctrl-alt-cmd-1".
struct Shortcut: Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    private static let modNames: [(name: String, mask: Int, symbol: String)] = [
        ("ctrl", controlKey, "⌃"), ("alt", optionKey, "⌥"), ("shift", shiftKey, "⇧"), ("cmd", cmdKey, "⌘"),
    ]

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// "ctrl-alt-cmd-1" → Shortcut. Tanınmayan tuş/modifier → nil.
    init?(spec: String) {
        var parts = spec.lowercased().split(separator: "-").map(String.init)
        // "ctrl-alt-minus" gibi değil ama "alt--" yazılırsa son parça boş kalır
        if spec.hasSuffix("--") { parts.append("-") }
        guard let keyName = parts.popLast(), let code = KeyNames.code(keyName) else { return nil }
        var mods: UInt32 = 0
        for p in parts {
            guard let m = Self.modNames.first(where: { $0.name == KeyNames.modifierAlias(p) }) else { return nil }
            mods |= UInt32(m.mask)
        }
        self.init(keyCode: code, modifiers: mods)
    }

    init(event: NSEvent) {
        var mods: UInt32 = 0
        let f = event.modifierFlags
        if f.contains(.control) { mods |= UInt32(controlKey) }
        if f.contains(.option) { mods |= UInt32(optionKey) }
        if f.contains(.shift) { mods |= UInt32(shiftKey) }
        if f.contains(.command) { mods |= UInt32(cmdKey) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods)
    }

    var spec: String {
        let mods = Self.modNames.filter { modifiers & UInt32($0.mask) != 0 }.map(\.name)
        return (mods + [KeyNames.name(keyCode)]).joined(separator: "-")
    }

    /// "⌃⌥⌘1" — tuş, o anki klavye düzenindeki karakterle (Türkçe Q'da [ yerine Ğ)
    var display: String {
        Self.modNames.filter { modifiers & UInt32($0.mask) != 0 }.map(\.symbol).joined()
            + KeyNames.display(keyCode)
    }

    /// Kaydedilebilir mi: en az bir ⌃ ⌥ ⌘ (yalnız ⇧ ya da modifier'sız tuş yazmayı bozar)
    var hasRequiredModifier: Bool {
        modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
    }
}

/// Tuş adları AeroSpace'in qwerty adları; hyprmac ve Amethyst adları takma ad olarak tanınır.
enum KeyNames {
    private static let table: [(String, Int)] = [
        ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D), ("e", kVK_ANSI_E),
        ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H), ("i", kVK_ANSI_I), ("j", kVK_ANSI_J),
        ("k", kVK_ANSI_K), ("l", kVK_ANSI_L), ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O),
        ("p", kVK_ANSI_P), ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
        ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X), ("y", kVK_ANSI_Y),
        ("z", kVK_ANSI_Z),
        ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3), ("4", kVK_ANSI_4),
        ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8), ("9", kVK_ANSI_9),
        ("minus", kVK_ANSI_Minus), ("equal", kVK_ANSI_Equal), ("period", kVK_ANSI_Period),
        ("comma", kVK_ANSI_Comma), ("slash", kVK_ANSI_Slash), ("backslash", kVK_ANSI_Backslash),
        ("quote", kVK_ANSI_Quote), ("semicolon", kVK_ANSI_Semicolon), ("backtick", kVK_ANSI_Grave),
        ("leftsquarebracket", kVK_ANSI_LeftBracket), ("rightsquarebracket", kVK_ANSI_RightBracket),
        ("space", kVK_Space), ("enter", kVK_Return), ("esc", kVK_Escape), ("backspace", kVK_Delete),
        ("tab", kVK_Tab), ("left", kVK_LeftArrow), ("right", kVK_RightArrow), ("up", kVK_UpArrow),
        ("down", kVK_DownArrow), ("delete", kVK_ForwardDelete), ("home", kVK_Home), ("end", kVK_End),
        ("pageup", kVK_PageUp), ("pagedown", kVK_PageDown),
        ("f1", kVK_F1), ("f2", kVK_F2), ("f3", kVK_F3), ("f4", kVK_F4), ("f5", kVK_F5), ("f6", kVK_F6),
        ("f7", kVK_F7), ("f8", kVK_F8), ("f9", kVK_F9), ("f10", kVK_F10), ("f11", kVK_F11), ("f12", kVK_F12),
        ("f13", kVK_F13), ("f14", kVK_F14), ("f15", kVK_F15), ("f16", kVK_F16), ("f17", kVK_F17),
        ("f18", kVK_F18), ("f19", kVK_F19), ("f20", kVK_F20),
    ]

    private static let aliases: [String: String] = [
        // hyprmac (hyprland/xkb adları)
        "return": "enter", "escape": "esc", "grave": "backtick", "bracketleft": "leftsquarebracket",
        "bracketright": "rightsquarebracket", "apostrophe": "quote", "equals": "equal",
        // Amethyst
        ",": "comma", ".": "period", "/": "slash", "\\": "backslash", ";": "semicolon", "'": "quote",
        "`": "backtick", "-": "minus", "=": "equal", "[": "leftsquarebracket", "]": "rightsquarebracket",
    ]

    private static let byName = Dictionary(uniqueKeysWithValues: table.map { ($0.0, UInt32($0.1)) })
    private static let byCode = Dictionary(table.map { (UInt32($0.1), $0.0) }, uniquingKeysWith: { a, _ in a })

    static func code(_ name: String) -> UInt32? {
        let n = name.lowercased()
        if let c = byName[aliases[n] ?? n] { return c }
        if n.hasPrefix("keycode:"), let c = UInt32(n.dropFirst(8)) { return c }
        return nil
    }

    static func name(_ code: UInt32) -> String { byCode[code] ?? "keycode:\(code)" }

    static func modifierAlias(_ m: String) -> String {
        switch m.lowercased() {
        case "control", "ctrl": return "ctrl"
        case "option", "alt", "opt": return "alt"
        case "command", "cmd", "super", "win": return "cmd"
        case "shift": return "shift"
        default: return m
        }
    }

    private static let symbols: [Int: String] = [
        kVK_Return: "↩", kVK_Space: "Space", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    static func display(_ code: UInt32) -> String {
        if let s = symbols[Int(code)] { return s }
        if let n = byCode[code], n.count > 1, n.hasPrefix("f"), Int(n.dropFirst()) != nil { return n.uppercased() }
        return layoutCharacter(code)?.uppercased() ?? name(code)
    }

    /// Fiziksel tuşun o anki klavye düzenindeki karakteri.
    private static func layoutCharacter(_ code: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
