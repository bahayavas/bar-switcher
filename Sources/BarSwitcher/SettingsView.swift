import SwiftUI

enum SettingsTab: String, CaseIterable {
    case shortcuts = "Kısayollar", general = "Genel", bars = "Barlar"
    var icon: String {
        switch self {
        case .shortcuts: return "keyboard"
        case .general: return "gearshape"
        case .bars: return "menubar.rectangle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var sw: Switcher
    @State var tab: SettingsTab

    init(initialTab: SettingsTab = .shortcuts) { _tab = State(initialValue: initialTab) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                ForEach(SettingsTab.allCases, id: \.self) { t in
                    Button {
                        sw.stopRecording()
                        tab = t
                    } label: {
                        Label(t.rawValue, systemImage: t.icon)
                            .font(TN.font(12, tab == t ? .semibold : .regular))
                            .foregroundStyle(tab == t ? TN.fg : TN.dim)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(tab == t ? TN.blue.opacity(0.18) : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tab == t ? TN.blue : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)

            switch tab {
            case .shortcuts: ShortcutsTab()
            case .general: GeneralTab()
            case .bars: BarsTab()
            }

            if let err = sw.error {
                Text(err).font(TN.font(11)).foregroundStyle(TN.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("settings.json") { NSWorkspace.shared.activateFileViewerSelecting([Switcher.settingsFile]) }
                    .buttonStyle(.plain)
                    .foregroundStyle(TN.dim)
                    .help("\(Switcher.settingsFile.path) — elle düzenlenebilir, kaydedince uygulama yeniden okur")
            }
            .font(TN.font(10))
        }
        .padding(20)
        .padding(.top, 12)
        .frame(width: 600)
        .background(TN.bg)
        .onAppear {
            sw.load()
            sw.scanConflicts()
        }
    }
}

// MARK: Kısayollar

struct ShortcutsTab: View {
    @EnvironmentObject var sw: Switcher

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Değiştirmek için kısayola tıkla, yeni tuşlara bas. ⌫ siler, ⎋ vazgeçer.")
                .font(TN.font(11)).foregroundStyle(TN.dim)

            VStack(spacing: 8) {
                ForEach(sw.actionIDs, id: \.self) { ShortcutRow(id: $0) }
            }

            HStack {
                Button("Varsayılana dön (⌃⌥⇧ + sıra, ⌃⌥⇧0, ⌃⌥⇧B)") { sw.resetShortcuts() }
                    .buttonStyle(.plain)
                    .foregroundStyle(TN.blue)
                Spacer()
            }
            .font(TN.font(11))

            Text("Çakışma kontrolü: WM Switcher kısayolları, AeroSpace aerospace.toml, hyprmac hyprmac.conf, "
                + "Amethyst (varsayılanlar + amethyst.yml) ve macOS klavye kısayolları.")
                .font(TN.font(10)).foregroundStyle(TN.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ShortcutRow: View {
    @EnvironmentObject var sw: Switcher
    let id: String

    private var bar: Bar? { sw.bars.first { $0.id == id } }
    private var isRecording: Bool { sw.recording == id }

    var body: some View {
        let current = sw.shortcut(id)
        let uses = sw.conflictsOf(id)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(bar?.badge ?? (id == "none" ? "∅" : "→"))
                    .font(TN.font(12, .bold))
                    .foregroundStyle(TN.purple)
                    .frame(width: 30, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(TN.card))
                Text(sw.actionName(id)).font(TN.font(13, .medium)).foregroundStyle(TN.fg)
                if let bar, !bar.installed {
                    Text("kurulu değil").font(TN.font(10)).foregroundStyle(TN.dim)
                }
                Spacer()

                Button {
                    isRecording ? sw.stopRecording() : sw.startRecording(id)
                } label: {
                    Text(isRecording ? "Tuşlara bas…" : current?.display ?? "Kısayol yok")
                        .font(TN.font(13, isRecording ? .regular : .semibold))
                        .foregroundStyle(isRecording ? TN.purple : (current == nil ? TN.dim : TN.fg))
                        .frame(minWidth: 130)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(isRecording ? TN.purple.opacity(0.15) : TN.card))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isRecording ? TN.purple : TN.border, lineWidth: isRecording ? 2 : 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                let isDefault = current == sw.defaultShortcut(id)
                Button {
                    sw.setShortcut(id, sw.defaultShortcut(id))
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(TN.dim)
                .help("Varsayılan: \(sw.defaultShortcut(id)?.display ?? "yok")")
                .disabled(isDefault)
                .opacity(isDefault ? 0.3 : 1)
            }

            if isRecording, let hint = sw.recordHint {
                Text(hint).font(TN.font(11)).foregroundStyle(TN.red).padding(.leading, 40)
            }
            if !isRecording {
                if sw.unregistered.contains(id) {
                    warning("Kaydedilemedi: başka bir uygulama bu kısayolu kullanıyor", TN.red)
                }
                ForEach(uses, id: \.self) { use in
                    warning("Çakışma — \(use.owner): \(use.description)", TN.yellow)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(TN.card.opacity(0.5)))
    }

    private func warning(_ text: String, _ color: Color) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(TN.font(11))
            .foregroundStyle(color)
            .padding(.leading, 40)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

// MARK: Genel

struct GeneralTab: View {
    @EnvironmentObject var sw: Switcher

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            toggle("Login'de başlat",
                   "Yalnızca Bar Switcher başlar ve son seçilen barı açar. Barların kendi \"launch at login\" ayarlarını açma.",
                   get: sw.loginEnabled, set: sw.setLogin)
            toggle("Geçişte bildirim göster",
                   "Bar değişince ya da yeniden başlatılınca macOS bildirimi.",
                   get: sw.settings.notifications, set: sw.setNotifications)
            toggle("Mac menü barını otomatik gizle",
                   "Bir bar seçiliyken macOS menü barı otomatik gizlenir, \"Hiçbiri\"de görünür. "
                   + "Kapatınca ilk değiştirilmeden önceki ayar geri yüklenir.",
                   get: sw.settings.manageMenuBar, set: sw.setManageMenuBar)
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ title: String, _ detail: String, get: Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(TN.font(13, .medium)).foregroundStyle(TN.fg)
                Text(detail).font(TN.font(11)).foregroundStyle(TN.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { get }, set: set))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(TN.blue)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(TN.card.opacity(0.5)))
    }
}

// MARK: Barlar

struct BarsTab: View {
    @EnvironmentObject var sw: Switcher
    @State private var dragging: String?

    var body: some View {
        let bars = sw.orderedBars
        VStack(alignment: .leading, spacing: 10) {
            Text("Sürükleyerek sırala (ya da ↑↓). Sıra rozet sırasını, varsayılan kısayol numarasını ve \"sıradaki bar\" "
                + "döngüsünü belirler. Gözle gizle/göster.")
                .font(TN.font(11)).foregroundStyle(TN.dim)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                ForEach(bars) { bar in
                    BarRow(bar: bar, first: bar.id == bars.first?.id, last: bar.id == bars.last?.id)
                        .opacity(dragging == bar.id ? 0.4 : 1)
                        .onDrag {
                            dragging = bar.id
                            return NSItemProvider(object: bar.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: ReorderDrop(target: bar.id, dragging: $dragging, sw: sw))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: bars.map(\.id))
        }
    }
}

/// Sürüklenen satır başka bir satırın üstüne gelince yer değiştirir (bırakmadan önce canlı)
struct ReorderDrop: DropDelegate {
    let target: String
    @Binding var dragging: String?
    let sw: Switcher

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            guard let from = dragging, from != target,
                  let i = sw.orderedBars.firstIndex(where: { $0.id == from }),
                  let j = sw.orderedBars.firstIndex(where: { $0.id == target }) else { return }
            sw.move(from: IndexSet(integer: i), to: j > i ? j + 1 : j)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

struct BarRow: View {
    @EnvironmentObject var sw: Switcher
    let bar: Bar
    let first: Bool
    let last: Bool

    var body: some View {
        let hidden = sw.settings.hidden.contains(bar.id)
        let number = sw.visibleBars.firstIndex { $0.id == bar.id }.map { $0 + 1 }
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(TN.dim)
            Text(number.map(String.init) ?? "–")
                .font(TN.font(12, .bold)).foregroundStyle(TN.dim).frame(width: 14)
            Text(bar.badge)
                .font(TN.font(12, .bold))
                .foregroundStyle(TN.purple)
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(TN.card))
            Text(bar.name).font(TN.font(13, .medium)).foregroundStyle(hidden ? TN.dim : TN.fg)
            if !bar.installed { Text("kurulu değil").font(TN.font(10)).foregroundStyle(TN.dim) }
            Spacer()
            Button { sw.moveBar(bar.id, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(first).opacity(first ? 0.25 : 1)
            Button { sw.moveBar(bar.id, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(last).opacity(last ? 0.25 : 1)
            Button { sw.setHidden(bar.id, !hidden) } label: {
                Image(systemName: hidden ? "eye.slash" : "eye")
                    .frame(width: 22)
            }
            .foregroundStyle(hidden ? TN.dim : TN.blue)
            .help(hidden ? "Göster" : "Gizle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(TN.fg)
        .font(TN.font(12))
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 10).fill(TN.card.opacity(hidden ? 0.25 : 0.5)))
    }
}
