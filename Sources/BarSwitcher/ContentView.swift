import SwiftUI

/// Tokyo Night
enum TN {
    static let bg = Color(hex: 0x1a1b26)
    static let card = Color(hex: 0x24283b)
    static let border = Color(hex: 0x3b4261)
    static let fg = Color(hex: 0xc0caf5)
    static let dim = Color(hex: 0x565f89)
    static let blue = Color(hex: 0x7aa2f7)
    static let purple = Color(hex: 0xbb9af7)
    static let red = Color(hex: 0xf7768e)
    static let green = Color(hex: 0x9ece6a)
    static let yellow = Color(hex: 0xe0af68)
    static let gradient = LinearGradient(colors: [blue, purple], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Maple Mono NF", size: size).weight(weight)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255)
    }
}

struct ContentView: View {
    @EnvironmentObject var sw: Switcher

    var body: some View {
        let bars = sw.visibleBars
        VStack(spacing: 16) {
            if bars.isEmpty {
                Text("Tüm barlar gizli — Ayarlar → Barlar").font(TN.font(13)).foregroundStyle(TN.dim)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                HStack(spacing: 12) {
                    ForEach(bars) { BarCard(bar: $0) }
                }
            }

            Button { sw.switchTo("none") } label: {
                HStack(spacing: 8) {
                    if sw.busy == "none" { ProgressView().controlSize(.small) }
                    Text("Hiçbiri (normal macOS menü barı)")
                    if let s = sw.shortcut("none") { Text(s.display).foregroundStyle(TN.dim) }
                }
                .font(TN.font(13, .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(sw.active == "none" ? TN.purple.opacity(0.18) : TN.card))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(sw.active == "none" ? TN.purple : TN.border, lineWidth: sw.active == "none" ? 2 : 1))
                .foregroundStyle(TN.fg)
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(sw.busy != nil)

            HStack(spacing: 14) {
                if let s = sw.shortcut("next") {
                    Text("Sıradaki: \(s.display)").foregroundStyle(TN.dim)
                }
                Spacer()
                Button {
                    (NSApp.delegate as? AppDelegate)?.showSettings()
                } label: {
                    Label("Ayarlar", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(TN.blue)
            }
            .font(TN.font(12))
            .foregroundStyle(TN.fg)

            if let err = sw.error {
                Text(err).font(TN.font(12)).foregroundStyle(TN.red).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .padding(.top, 10)
        .frame(width: max(520, CGFloat(bars.count) * 142 + 36))
        .background(TN.bg)
        .onAppear { sw.refresh() }
    }
}

struct BarCard: View {
    @EnvironmentObject var sw: Switcher
    let bar: Bar

    private var isActive: Bool { sw.active == bar.id }

    var body: some View {
        VStack(spacing: 6) {
            Button { sw.switchTo(bar.id) } label: {
                VStack(spacing: 6) {
                    ZStack {
                        Text(bar.badge)
                            .font(TN.font(38, .bold))
                            .foregroundStyle(isActive ? AnyShapeStyle(TN.gradient) : AnyShapeStyle(TN.fg))
                        if sw.busy == bar.id { ProgressView().controlSize(.small).offset(y: 32) }
                    }
                    .frame(height: 58)
                    Text(bar.name).font(TN.font(13, .semibold)).foregroundStyle(TN.fg)
                    Text(status).font(TN.font(11)).foregroundStyle(isActive ? TN.green : TN.dim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(isActive ? TN.blue.opacity(0.15) : TN.card))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isActive ? AnyShapeStyle(TN.gradient) : AnyShapeStyle(TN.border),
                                  lineWidth: isActive ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!bar.installed || sw.busy != nil)

            Button("Ayar dosyasını aç") { sw.openConfig(bar) }
                .buttonStyle(.plain)
                .foregroundStyle(bar.configPath != nil ? TN.blue : TN.dim)
                .disabled(bar.configPath == nil)
                .help(bar.configPath ?? "Henüz yok — \(bar.name) bir kez çalışınca oluşur: \(bar.configPaths.first ?? "")")

            Button {
                sw.restart(bar.id)
            } label: {
                Label("Yeniden başlat", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(isActive ? TN.purple : TN.dim)
            .disabled(!isActive || sw.busy != nil)
            .help(isActive ? "Ayar değiştirdikten sonra" : "Yalnızca aktif bar yeniden başlatılabilir")
        }
        .font(TN.font(10.5))
        .frame(width: 130)
        .opacity(bar.installed ? 1 : 0.35)
        .saturation(bar.installed ? 1 : 0)
    }

    private var status: String {
        if !bar.installed { return "kurulu değil" }
        if isActive { return "● aktif" }
        return sw.shortcut(bar.id)?.display ?? " "
    }
}
