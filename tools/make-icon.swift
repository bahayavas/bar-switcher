// Uygulama ikonunu çizer: swift tools/make-icon.swift <çıktı.png>  (1024x1024)
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS ikon ızgarası: 824pt kare, 100pt kenar boşluğu
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
c(0x1a1b26).setFill()
shape.fill()
let grad = NSGradient(starting: c(0x7aa2f7), ending: c(0xbb9af7))!
let border = NSBezierPath(roundedRect: body.insetBy(dx: 8, dy: 8), xRadius: 178, yRadius: 178)
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext.current!.cgContext
ctx.addPath(border.cgPath)
ctx.setLineWidth(16)
ctx.replacePathWithStrokedPath()
ctx.clip()
grad.draw(in: body, angle: -45)
NSGraphicsContext.restoreGraphicsState()

// Üstte iki bar şeridi: aktif (dolu, hap öğeli) ve sıradaki (soluk) — aralarında geçiş
let inner = body.insetBy(dx: 110, dy: 0)
func barStrip(y: CGFloat, color: NSColor, alpha: CGFloat, pills: [(CGFloat, CGFloat, NSColor)]) {
    let r = NSRect(x: inner.minX, y: y, width: inner.width, height: 120)
    let p = NSBezierPath(roundedRect: r, xRadius: 60, yRadius: 60)
    color.withAlphaComponent(0.16 * alpha).setFill()
    p.fill()
    color.withAlphaComponent(alpha).setStroke()
    p.lineWidth = 14
    p.stroke()
    for (x, w, col) in pills {
        let pr = NSRect(x: r.minX + x, y: r.midY - 24, width: w, height: 48)
        let pp = NSBezierPath(roundedRect: pr, xRadius: 24, yRadius: 24)
        col.withAlphaComponent(alpha).setFill()
        pp.fill()
    }
}
barStrip(y: 680, color: c(0x7aa2f7), alpha: 1,
         pills: [(40, 48, c(0x7aa2f7)), (108, 48, c(0xbb9af7)), (176, 48, c(0x7dcfff)), (430, 120, c(0x9ece6a))])
barStrip(y: 210, color: c(0xbb9af7), alpha: 0.55,
         pills: [(40, 160, c(0xbb9af7)), (360, 48, c(0x7aa2f7)), (428, 120, c(0x7dcfff))])

let arrow = NSAttributedString(string: "⇅", attributes: [
    .font: NSFont.systemFont(ofSize: 250, weight: .bold),
    .foregroundColor: c(0xc0caf5),
])
let s = arrow.size()
arrow.draw(at: NSPoint(x: body.midX - s.width / 2, y: 512 - s.height / 2 - 10))

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
