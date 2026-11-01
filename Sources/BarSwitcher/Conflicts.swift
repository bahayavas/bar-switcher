import AppKit
import Carbon

/// Bir kısayolun başka bir yerde kullanılıp kullanılmadığını bulur:
///   WM Switcher  ~/.config/wm-switcher/shortcuts.json (yoksa varsayılan ⌃⌥⌘ + sıra)
///   AeroSpace    aerospace.toml [mode.main.binding]
///   hyprmac      hyprmac.conf `bind = MODS, KEY, ...`
///   Amethyst     uygulamadaki default.amethyst + amethyst.yml
///   macOS        com.apple.symbolichotkeys (Sistem Ayarları → Klavye → Klavye Kısayolları)
enum Conflicts {
    struct Use: Hashable {
        let owner: String
        let description: String
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static func scan() -> [Shortcut: [Use]] {
        var out: [Shortcut: [Use]] = [:]
        func add(_ owner: String, _ uses: [(Shortcut, String)]) {
            for (s, d) in uses { out[s, default: []].append(Use(owner: owner, description: d)) }
        }
        add("WM Switcher", wmSwitcher())
        let fm = FileManager.default
        if fm.fileExists(atPath: "/Applications/AeroSpace.app") {
            add("AeroSpace", aerospace(home + "/.config/aerospace/aerospace.toml"))
        }
        if fm.fileExists(atPath: "/Applications/hyprmac.app") {
            add("hyprmac", hyprmac(home + "/.config/wisp/hyprmac.conf"))
        }
        if fm.fileExists(atPath: "/Applications/Amethyst.app") {
            add("Amethyst", amethyst(appPath: "/Applications/Amethyst.app", yml: home + "/.config/amethyst/amethyst.yml"))
        }
        add("macOS", system())
        return out
    }

    private static func lines(_ path: String) -> [String] {
        ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").components(separatedBy: "\n")
    }

    // MARK: WM Switcher

    static func wmSwitcher() -> [(Shortcut, String)] {
        let conf = lines(home + "/wm-switcher/wms.conf").compactMap { line -> (String, String)? in
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, !s.hasPrefix("#") else { return nil }
            let f = s.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            return f.count >= 2 ? (f[0], f[1]) : nil
        }
        guard !conf.isEmpty else { return [] }
        var saved: [String: String] = [:]
        if let data = FileManager.default.contents(atPath: home + "/.config/wm-switcher/shortcuts.json") {
            saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] ?? [:]
        }
        var out: [(Shortcut, String)] = []
        for (i, (id, name)) in (conf + [("none", "Hepsini kapat")]).enumerated() {
            let spec = saved[id] ?? (id == "none" ? "ctrl-alt-cmd-0" : (i < 9 ? "ctrl-alt-cmd-\(i + 1)" : ""))
            if let s = Shortcut(spec: spec) { out.append((s, name)) }
        }
        return out
    }

    // MARK: AeroSpace

    static func aerospace(_ path: String) -> [(Shortcut, String)] {
        var inMain = false
        var out: [(Shortcut, String)] = []
        for raw in lines(path) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inMain = line == "[mode.main.binding]"
                continue
            }
            guard inMain, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            guard let s = Shortcut(spec: key) else { continue }
            var cmd = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let hash = cmd.range(of: " #") { cmd = String(cmd[..<hash.lowerBound]) }
            cmd = cmd.replacingOccurrences(of: "'", with: "")
            out.append((s, "\(key) → \(cmd.prefix(40))"))
        }
        return out
    }

    // MARK: hyprmac

    static func hyprmac(_ path: String) -> [(Shortcut, String)] {
        var vars: [String: String] = [:]
        var out: [(Shortcut, String)] = []
        for raw in lines(path) {
            let line = raw.components(separatedBy: "#")[0].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("$"), let eq = line.firstIndex(of: "=") {
                vars[line[..<eq].trimmingCharacters(in: .whitespaces)] =
                    line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                continue
            }
            guard line.hasPrefix("bind"), let eq = line.firstIndex(of: "=") else { continue }
            let fields = line[line.index(after: eq)...].split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 3 else { continue }
            let mods = fields[0].split(separator: " ").flatMap { tok -> [String] in
                let t = String(tok)
                return (vars[t] ?? t).split(separator: " ").map { KeyNames.modifierAlias(String($0)) }
            }
            guard let s = Shortcut(spec: (mods + [fields[1]]).joined(separator: "-")) else { continue }
            let what = fields[2...].filter { !$0.isEmpty }.joined(separator: " ")
            out.append((s, "\(fields[0]), \(fields[1]) → \(what.prefix(40))"))
        }
        return out
    }

    // MARK: Amethyst

    static func amethyst(appPath: String, yml: String) -> [(Shortcut, String)] {
        let defaultsPath = appPath + "/Contents/Resources/default.amethyst"
        guard let data = FileManager.default.contents(atPath: defaultsPath),
              var conf = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        for (k, v) in parseYAML(yml) { conf[k] = v }

        let mod1 = conf["mod1"] as? [String] ?? []
        let mod2 = conf["mod2"] as? [String] ?? []
        var out: [(Shortcut, String)] = []
        for (command, value) in conf {
            guard let b = value as? [String: Any], let key = b["key"] as? String else { continue }
            let mods: [String]
            switch b["mod"] as? String {
            case "mod1": mods = mod1
            case "mod2": mods = mod2
            default: continue
            }
            let spec = (mods.map { KeyNames.modifierAlias($0) } + [key]).joined(separator: "-")
            if let s = Shortcut(spec: spec) { out.append((s, command)) }
        }
        return out
    }

    /// amethyst.yml için yeterli küçük YAML: üst düzey anahtarlar, `- liste` ve tek seviye `alt: değer`.
    static func parseYAML(_ path: String) -> [String: Any] {
        var out: [String: Any] = [:]
        var current: String?
        var list: [String] = []
        var map: [String: String] = [:]
        func flush() {
            guard let c = current else { return }
            if !list.isEmpty { out[c] = list } else if !map.isEmpty { out[c] = map }
            list = []; map = [:]
        }
        for raw in lines(path) {
            let noComment = raw.components(separatedBy: "#")[0]
            guard !noComment.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let indented = noComment.first == " " || noComment.first == "\t"
            let line = noComment.trimmingCharacters(in: .whitespaces)
            if !indented {
                flush()
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                current = parts[0]
                if parts.count == 2, !parts[1].isEmpty { out[parts[0]] = unquote(parts[1]); current = nil }
            } else if line.hasPrefix("- ") {
                list.append(unquote(String(line.dropFirst(2))))
            } else if let colon = line.firstIndex(of: ":") {
                map[line[..<colon].trimmingCharacters(in: .whitespaces)] =
                    unquote(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            }
        }
        flush()
        return out
    }

    private static func unquote(_ s: String) -> String {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    }

    // MARK: macOS

    /// Bilinen sistem kısayolları: id → (ad, varsayılan). Kullanıcı değiştirdiyse plist'teki değer geçerli.
    private static let systemNames: [Int: (String, String?)] = [
        28: ("Ekran görüntüsü", "shift-cmd-3"), 29: ("Ekran görüntüsü → pano", "ctrl-shift-cmd-3"),
        30: ("Seçili alanın görüntüsü", "shift-cmd-4"), 31: ("Seçili alan → pano", "ctrl-shift-cmd-4"),
        184: ("Ekran görüntüsü araçları", "shift-cmd-5"),
        64: ("Spotlight", "cmd-space"), 65: ("Finder arama penceresi", "alt-cmd-space"),
        60: ("Önceki giriş kaynağı", "ctrl-space"), 61: ("Sonraki giriş kaynağı", "ctrl-alt-space"),
        32: ("Mission Control", "ctrl-up"), 33: ("Uygulama pencereleri", "ctrl-down"),
        79: ("Soldaki masaüstü", "ctrl-left"), 81: ("Sağdaki masaüstü", "ctrl-right"),
        36: ("Masaüstünü göster", "f11"), 162: ("Erişilebilirlik kısayolları", "alt-cmd-f5"),
        7: ("Odak: menü bar", "ctrl-f2"), 8: ("Odak: Dock", "ctrl-f3"), 9: ("Odak: aktif pencere", "ctrl-f4"),
        10: ("Odak: araç çubuğu", "ctrl-f5"), 11: ("Odak: yüzen pencere", "ctrl-f6"),
        27: ("Sonraki pencere", "cmd-backtick"), 98: ("Yardım menüsü", "shift-cmd-slash"),
        118: ("Masaüstü 1", "ctrl-1"), 119: ("Masaüstü 2", "ctrl-2"), 120: ("Masaüstü 3", "ctrl-3"),
        121: ("Masaüstü 4", "ctrl-4"), 122: ("Masaüstü 5", "ctrl-5"), 123: ("Masaüstü 6", "ctrl-6"),
    ]

    static func system() -> [(Shortcut, String)] {
        let raw = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)
        let table = raw as? [String: Any] ?? [:]
        var out: [(Shortcut, String)] = []
        var seen: Set<Int> = []
        for (key, value) in table {
            guard let id = Int(key), let entry = value as? [String: Any] else { continue }
            seen.insert(id)
            guard (entry["enabled"] as? Bool ?? (entry["enabled"] as? Int == 1)) else { continue }
            let name = systemNames[id]?.0 ?? "sistem kısayolu #\(id)"
            if let params = (entry["value"] as? [String: Any])?["parameters"] as? [Int], params.count == 3,
               params[1] != 65535 {
                out.append((Shortcut(keyCode: UInt32(params[1]), modifiers: carbon(cocoa: params[2])), name))
            } else if let spec = systemNames[id]?.1, let s = Shortcut(spec: spec) {
                out.append((s, name))
            }
        }
        // Plist'te hiç olmayanlar varsayılanla açıktır
        for (id, (name, spec)) in systemNames where !seen.contains(id) {
            if let spec, let s = Shortcut(spec: spec) { out.append((s, name)) }
        }
        return out
    }

    private static func carbon(cocoa: Int) -> UInt32 {
        let f = NSEvent.ModifierFlags(rawValue: UInt(cocoa))
        var m = 0
        if f.contains(.control) { m |= controlKey }
        if f.contains(.option) { m |= optionKey }
        if f.contains(.shift) { m |= shiftKey }
        if f.contains(.command) { m |= cmdKey }
        return UInt32(m)
    }
}
