import Foundation

/// ~/.config/bar-switcher/settings.json — elle düzenlenebilir, uygulama değişikliği görüp yeniden okur.
/// Eksik anahtar varsayılanı alır, bilinmeyen anahtar yok sayılır.
struct Settings: Codable, Equatable {
    /// Barların sırası (rozet sırası, varsayılan kısayol numarası, "sıradaki" döngüsü)
    var order: [String] = []
    /// Listede gizlenen barlar (pencere, Dock menüsü, kısayollar, "sıradaki" döngüsü)
    var hidden: [String] = []
    /// Eylem id'si → "ctrl-alt-shift-1" biçiminde kısayol. "" = kısayol yok. Olmayan eylem varsayılanı alır.
    /// Eylemler: bar id'leri, "none", "next".
    var shortcuts: [String: String] = [:]
    var launchAtLogin = true
    var notifications = true
    /// switch.sh macOS menü barı otomatik gizlemeyi yönetsin mi
    var manageMenuBar = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        order = try c.decodeIfPresent([String].self, forKey: .order) ?? d.order
        hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? d.hidden
        shortcuts = try c.decodeIfPresent([String: String].self, forKey: .shortcuts) ?? d.shortcuts
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        notifications = try c.decodeIfPresent(Bool.self, forKey: .notifications) ?? d.notifications
        manageMenuBar = try c.decodeIfPresent(Bool.self, forKey: .manageMenuBar) ?? d.manageMenuBar
    }

    static func load(from url: URL) throws -> Settings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try JSONDecoder().decode(Settings.self, from: data)
    }

    func save(to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
