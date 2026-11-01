import AppKit
import Carbon
import Darwin
import ServiceManagement
import UserNotifications

/// bars.conf'taki bir satır.
struct Bar: Identifiable, Equatable {
    let id: String
    let name: String
    let kind: String
    let bundleID: String
    let path: String
    let configPaths: [String]
    let badge: String

    var installed: Bool {
        kind == "binary" ? FileManager.default.isExecutableFile(atPath: path) : FileManager.default.fileExists(atPath: path)
    }
    var isUbersicht: Bool { kind.hasPrefix("ubersicht") }
    /// Var olan ilk ayar yolu
    var configPath: String? { configPaths.first { FileManager.default.fileExists(atPath: $0) } }
}

@MainActor
final class Switcher: ObservableObject {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bar-switcher")
    static let script = dir.appendingPathComponent("switch.sh").path
    static let conf = dir.appendingPathComponent("bars.conf").path
    static let stateDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/bar-switcher")
    static let settingsFile = stateDir.appendingPathComponent("settings.json")
    static let currentFile = stateDir.appendingPathComponent("current")

    @Published private(set) var bars: [Bar] = []
    @Published private(set) var settings = Settings()
    /// Şu an çalışan barın id'si, hiçbiri çalışmıyorsa "none".
    @Published private(set) var active = "none"
    /// Geçiş/yeniden başlatma sürerken hedef id'si.
    @Published private(set) var busy: String?
    @Published var error: String?
    @Published private(set) var loginEnabled = SMAppService.mainApp.status == .enabled

    /// Başka bir uygulama aldığı için kaydedilemeyen eylemler.
    @Published private(set) var unregistered: Set<String> = []
    /// WM'lerin, WM Switcher'ın ve macOS'un kullandığı kısayollar (Ayarlar açılınca taranır).
    @Published private(set) var conflicts: [Shortcut: [Conflicts.Use]] = [:]
    /// Kısayolu kaydedilmekte olan eylem.
    @Published private(set) var recording: String?
    @Published var recordHint: String?
    private var recordMonitor: Any?

    private var appsObservation: NSKeyValueObservation?
    private var timer: Timer?
    private var settingsStamp: Date?
    private var currentStamp: Date?
    /// Snapshot/test modunda dosyaya yazma, kısayol kaydetme yok
    private let passive: Bool

    init(passive: Bool = false) {
        self.passive = passive
        load()
        loadSettings(initial: true)
        refresh()
        guard !passive else { return }
        // NSWorkspace launch bildirimleri LSUIElement uygulamalarda gelmiyor; runningApplications KVO hepsini görür.
        appsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, change in
            let launched = (change.newValue ?? []).compactMap(\.bundleIdentifier)
            Task { @MainActor in self?.appsChanged(launched: launched) }
        }
        // SketchyBar bir uygulama değil (KVO görmez); settings.json elle düzenlenebilir → yokla
        watchDockRestart()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Dock yeniden başlayınca (killall Dock) rozet kaybolur, aynı değeri tekrar yazmak AppKit'te etkisiz
    private var dockObserver: Any?

    private func watchDockRestart() {
        dockObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.apple.dock" else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                MainActor.assumeIsolated {
                    self?.refresh()
                    self?.updateBadge(force: true)
                }
            }
        }
    }

    private func tick() {
        if stamp(Self.settingsFile) != settingsStamp { loadSettings() }
        if busy == nil { refresh() }
    }

    private func stamp(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Bir bar switcher dışından açıldıysa (Spotlight, Finder…) yeni açılan kazanır.
    private func appsChanged(launched: [String]) {
        guard busy == nil, let bar = visibleBars.first(where: { launched.contains($0.bundleID) }),
              bar.id != active else {
            refresh()
            return
        }
        if bar.isUbersicht {
            // simple-bar mı Übersicht mi: kayıtlı mod korunur
            let saved = savedSelection()
            if bars.first(where: { $0.id == saved })?.isUbersicht == true { return refresh() }
        }
        switchTo(bar.id)
    }

    func load() {
        guard let text = try? String(contentsOfFile: Self.conf, encoding: .utf8) else {
            error = "bars.conf okunamadı: \(Self.conf)"
            return
        }
        bars = text.split(separator: "\n").compactMap { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty, !s.hasPrefix("#") else { return nil }
            let f = s.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 7 else { return nil }
            let cfgs = f[5].split(separator: ",").map { ($0.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath }
            return Bar(id: f[0], name: f[1], kind: f[2], bundleID: f[3], path: f[4], configPaths: cfgs, badge: f[6])
        }
    }

    // MARK: Ayarlar

    /// settings.json'daki sıra; dosyada olmayan barlar bars.conf sırasıyla sona eklenir
    var orderedBars: [Bar] {
        let known = settings.order.compactMap { id in bars.first { $0.id == id } }
        return known + bars.filter { !settings.order.contains($0.id) }
    }

    var visibleBars: [Bar] { orderedBars.filter { !settings.hidden.contains($0.id) } }

    func loadSettings(initial: Bool = false) {
        settingsStamp = stamp(Self.settingsFile)
        do {
            if let s = try Settings.load(from: Self.settingsFile) {
                let old = settings
                settings = s
                if initial || old.launchAtLogin != s.launchAtLogin { syncLogin() }
                if !initial, old.manageMenuBar != s.manageMenuBar { applyMenuBarSetting() }
                if error?.hasPrefix("settings.json") == true { error = nil }
            } else if !passive {
                // İlk açılış: varsayılanları yaz
                settings.order = bars.map(\.id)
                saveSettings()
                syncLogin()
            }
        } catch {
            self.error = "settings.json okunamadı, eski ayarlar kullanılıyor: \(Self.describe(error))"
        }
        if !passive { applyHotKeys() }
    }

    private static func describe(_ error: Error) -> String {
        if case DecodingError.dataCorrupted(let c) = error {
            return (c.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String ?? c.debugDescription
        }
        return error.localizedDescription
    }

    private func saveSettings() {
        guard !passive else { return }
        do {
            try FileManager.default.createDirectory(at: Self.stateDir, withIntermediateDirectories: true)
            try settings.save(to: Self.settingsFile)
            settingsStamp = stamp(Self.settingsFile)
        } catch {
            self.error = "settings.json kaydedilemedi: \(error.localizedDescription)"
        }
    }

    private func update(_ change: (inout Settings) -> Void) {
        change(&settings)
        if settings.order.isEmpty || Set(settings.order) != Set(bars.map(\.id)) {
            settings.order = orderedBars.map(\.id)
        }
        saveSettings()
        applyHotKeys()
    }

    func move(from: IndexSet, to: Int) {
        var ids = orderedBars.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        update { $0.order = ids }
    }

    func moveBar(_ id: String, by delta: Int) {
        var ids = orderedBars.map(\.id)
        guard let i = ids.firstIndex(of: id), ids.indices.contains(i + delta) else { return }
        ids.swapAt(i, i + delta)
        update { $0.order = ids }
    }

    func setHidden(_ id: String, _ hide: Bool) {
        update { s in
            s.hidden.removeAll { $0 == id }
            if hide { s.hidden.append(id) }
        }
    }

    func setNotifications(_ on: Bool) {
        update { $0.notifications = on }
        if on { requestNotificationPermission() }
    }

    func setManageMenuBar(_ on: Bool) {
        update { $0.manageMenuBar = on }
        applyMenuBarSetting()
    }

    /// Açılınca o anki bara göre ayarla; kapanınca yedekteki değere dön
    private func applyMenuBarSetting() {
        run(settings.manageMenuBar ? [active] : ["menubar-restore"]) { _, _ in }
    }

    func setLogin(_ on: Bool) {
        update { $0.launchAtLogin = on }
        syncLogin()
    }

    private func syncLogin() {
        guard !passive else { return }
        let on = settings.launchAtLogin
        let enabled = SMAppService.mainApp.status == .enabled
        if on != enabled {
            do {
                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                self.error = "Login ayarı değişmedi: \(error.localizedDescription)"
            }
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
        if on, SMAppService.mainApp.status == .requiresApproval {
            error = "System Settings → General → Login Items'ta Bar Switcher'a izin ver."
        }
    }

    // MARK: Kısayollar

    /// Ayarlar'daki sıra: görünen barlar, "Hiçbiri", "Sıradaki"
    var actionIDs: [String] { visibleBars.map(\.id) + ["none", "next"] }

    func actionName(_ id: String) -> String {
        switch id {
        case "none": return "Hiçbiri (normal macOS)"
        case "next": return "Sıradaki bar"
        default: return bars.first { $0.id == id }?.name ?? id
        }
    }

    /// Varsayılan: ⌃⌥⇧ + görünen sıradaki numara (1-9), Hiçbiri ⌃⌥⇧0, Sıradaki ⌃⌥⇧B
    func defaultShortcut(_ id: String) -> Shortcut? {
        switch id {
        case "none": return Shortcut(spec: "ctrl-alt-shift-0")
        case "next": return Shortcut(spec: "ctrl-alt-shift-b")
        default:
            guard let i = visibleBars.firstIndex(where: { $0.id == id }), i < 9 else { return nil }
            return Shortcut(spec: "ctrl-alt-shift-\(i + 1)")
        }
    }

    func shortcut(_ id: String) -> Shortcut? {
        if let spec = settings.shortcuts[id] { return spec.isEmpty ? nil : Shortcut(spec: spec) }
        return defaultShortcut(id)
    }

    func setShortcut(_ id: String, _ s: Shortcut?) {
        // Varsayılana eşitse kaydetme: sıra değişince numara da değişsin
        update { st in
            if s == defaultShortcut(id) { st.shortcuts[id] = nil } else { st.shortcuts[id] = s?.spec ?? "" }
        }
    }

    func resetShortcuts() { update { $0.shortcuts = [:] } }

    func applyHotKeys() {
        guard recording == nil else { return }
        HotKeys.unregisterAll()
        var failed: Set<String> = []
        for id in actionIDs {
            guard let s = shortcut(id) else { continue }
            let ok = HotKeys.register(s) { [weak self] in
                MainActor.assumeIsolated { id == "next" ? self?.next() : self?.switchTo(id) }
            }
            if !ok { failed.insert(id) }
        }
        unregistered = failed
    }

    func scanConflicts() { conflicts = Conflicts.scan() }

    /// Bu eylemin kısayolu başka nerede kullanılıyor (switcher içi tekrarlar dahil)
    func conflictsOf(_ id: String) -> [Conflicts.Use] {
        guard let s = shortcut(id) else { return [] }
        let dup = actionIDs.filter { $0 != id && shortcut($0) == s }
            .map { Conflicts.Use(owner: "Bar Switcher", description: actionName($0)) }
        return dup + (conflicts[s] ?? [])
    }

    func startRecording(_ id: String) {
        stopRecording()
        recording = id
        recordHint = nil
        // Kayıt sırasında global kısayollar kapalı: mevcut bir kısayola basınca geçiş yapmasın
        HotKeys.unregisterAll()
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleRecord(event) }
            return nil
        }
    }

    func stopRecording() {
        if let m = recordMonitor { NSEvent.removeMonitor(m) }
        recordMonitor = nil
        if recording != nil {
            recording = nil
            applyHotKeys()
        }
    }

    private func handleRecord(_ event: NSEvent) {
        guard let id = recording else { return }
        let s = Shortcut(event: event)
        let plain = event.modifierFlags.intersection([.control, .option, .command, .shift]).isEmpty
        if plain && s.keyCode == UInt32(kVK_Escape) {
            stopRecording()
        } else if plain && (s.keyCode == UInt32(kVK_Delete) || s.keyCode == UInt32(kVK_ForwardDelete)) {
            stopRecording()
            setShortcut(id, nil)
        } else if !s.hasRequiredModifier {
            recordHint = "En az bir ⌃ ⌥ ⌘ tuşu gerekli"
        } else if let other = actionIDs.first(where: { $0 != id && shortcut($0) == s }) {
            recordHint = "\(s.display) zaten \(actionName(other)) için kullanılıyor"
        } else {
            stopRecording()
            setShortcut(id, s)
        }
    }

    // MARK: Durum ve geçiş

    private func savedSelection() -> String {
        ((try? String(contentsOf: Self.currentFile, encoding: .utf8)) ?? "none")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isRunning(_ bar: Bar) -> Bool {
        if bar.kind == "binary" { return Self.processRunning(named: (bar.path as NSString).lastPathComponent) }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bar.bundleID).isEmpty
    }

    /// libproc ile süreç adına göre arama (pgrep -x gibi)
    static func processRunning(named name: String) -> Bool {
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return false }
        var buf = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(Int(bytes)) where pid > 0 {
            if proc_name(pid, &buf, UInt32(buf.count)) > 0, String(cString: buf) == name { return true }
        }
        return false
    }

    func refresh() {
        let saved = savedSelection()
        var now = "none"
        for bar in orderedBars where isRunning(bar) {
            if bar.isUbersicht {
                now = bars.first(where: { $0.id == saved })?.isUbersicht == true ? saved : "ubersicht"
            } else {
                now = bar.id
            }
            if now == saved { break }   // birden fazla çalışıyorsa kayıtlı olan öncelikli
        }
        active = now
        loginEnabled = SMAppService.mainApp.status == .enabled
        updateBadge()
    }

    /// Uygulama Dock'a bağlanmadan önce yazılan rozet görünmüyor, AppKit de aynı değeri tekrar göndermiyor:
    /// açılışta ve Dock yeniden başlayınca force ile önce başka bir değer yazılır.
    func updateBadge(force: Bool = false) {
        guard !passive else { return }
        let badge = bars.first { $0.id == active }?.badge
        if force { NSApp.dockTile.badgeLabel = badge == nil ? " " : nil }
        NSApp.dockTile.badgeLabel = badge
    }

    func switchTo(_ id: String) {
        guard busy == nil, !passive else { return }
        if id != "none", bars.first(where: { $0.id == id })?.installed != true { return }
        busy = id
        error = nil
        run([id]) { [weak self] status, stderr in
            guard let self else { return }
            busy = nil
            refresh()
            if status != 0 {
                error = stderr.isEmpty ? "switch.sh çıkış kodu \(status)" : stderr
            } else {
                notify("Bar: \(id == "none" ? "Hiçbiri (normal macOS menü barı)" : actionName(id))")
            }
        }
    }

    /// Görünen ve kurulu barlar arasında sıradakine geç (Hiçbiri → ilk bar)
    func next() {
        let list = visibleBars.filter(\.installed)
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == active }.map { ($0 + 1) % list.count } ?? 0
        switchTo(list[i].id)
    }

    func restart(_ id: String) {
        guard busy == nil, !passive, active == id else { return }
        busy = id
        error = nil
        run(["restart", id]) { [weak self] status, stderr in
            guard let self else { return }
            busy = nil
            refresh()
            if status != 0 {
                error = stderr.isEmpty ? "yeniden başlatılamadı (\(status))" : stderr
            } else {
                notify("\(actionName(id)) yeniden başlatıldı")
            }
        }
    }

    /// Login'de: son seçilen barı başlat.
    func restore() {
        busy = "restore"
        run(["restore"]) { [weak self] _, _ in
            self?.busy = nil
            self?.refresh()
        }
    }

    func openConfig(_ bar: Bar) {
        guard let path = bar.configPath else { return }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        // Klasör → Finder, dosya → varsayılan metin editörü
        p.arguments = isDir.boolValue ? [path] : ["-t", path]
        try? p.run()
    }

    // MARK: Bildirim

    func requestNotificationPermission() {
        guard !passive else { return }
        // .badge şart: macOS bildirim izni verilen uygulamalarda Dock rozetini de bu yetkiye bağlıyor
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { _, _ in }
    }

    private func notify(_ text: String) {
        guard settings.notifications else { return }
        let content = UNMutableNotificationContent()
        content.title = "Bar Switcher"
        content.body = text
        let req = UNNotificationRequest(identifier: "switch", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: switch.sh

    private func run(_ args: [String], done: @escaping @MainActor (Int32, String) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [Self.script] + args
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = FileHandle.nullDevice
        p.terminationHandler = { proc in
            let data = errPipe.fileHandleForReading.readDataToEndOfFile()
            // Son satır en anlamlısı (ör. "başka bir geçiş sürüyor")
            let msg = String(decoding: data, as: UTF8.self)
                .split(separator: "\n").last.map { $0.replacingOccurrences(of: "[bar-switcher] ", with: "") } ?? ""
            let status = proc.terminationStatus
            Task { @MainActor in done(status, status == 0 ? "" : msg) }
        }
        do { try p.run() } catch {
            done(-1, "switch.sh çalıştırılamadı: \(error.localizedDescription)")
        }
    }
}
