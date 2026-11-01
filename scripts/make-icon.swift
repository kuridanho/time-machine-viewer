// アプリのアイコンを描き、Resources/AppIcon.icns を作る。
// 使い方: swift scripts/make-icon.swift
// 図柄: 夜の青の角丸四角に、進捗の輪と、ディスクイメージのバンドを表す三段の板を重ねる。
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let size: CGFloat = 1024

func draw(_ ctx: CGContext) {
    let cs = CGColorSpaceCreateDeviceRGB()
    func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }

    // macOS の標準の枠: 1024 の中に 824 の角丸四角、角の半径は約 185。
    let inset: CGFloat = 100
    let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x0E1A33))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [color(0x23407A), color(0x0B1530)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    ctx.restoreGState()

    let center = CGPoint(x: size / 2, y: size / 2 + 6)
    let radius: CGFloat = 270
    let lineWidth: CGFloat = 56

    // 輪の下地。
    ctx.setLineWidth(lineWidth)
    ctx.setStrokeColor(color(0xFFFFFF, 0.14))
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // 進んだ分の弧。12時から時計回りに約7割。
    let start = CGFloat.pi / 2
    let end = start - .pi * 2 * 0.7
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    ctx.setLineWidth(lineWidth)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let arc = CGGradient(colorsSpace: cs, colors: [color(0xFFC861), color(0xFF8A3D)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(arc, start: CGPoint(x: center.x + radius, y: center.y + radius),
                           end: CGPoint(x: center.x - radius, y: center.y - radius), options: [])
    ctx.restoreGState()

    // 弧の先端の点。
    let tip = CGPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillEllipse(in: CGRect(x: tip.x - 17, y: tip.y - 17, width: 34, height: 34))

    // 中のバンド三段。一段だけ明るくして、いま開いている一枚を表す。
    let bandWidth: CGFloat = 250, bandHeight: CGFloat = 62, gap: CGFloat = 22
    for i in 0..<3 {
        let y = center.y - bandHeight * 1.5 - gap + CGFloat(i) * (bandHeight + gap)
        let rect = CGRect(x: center.x - bandWidth / 2, y: y, width: bandWidth, height: bandHeight)
        let path = CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(i == 1 ? color(0xFFFFFF) : color(0xFFFFFF, 0.38))
        ctx.fillPath()
        // 板の右端の小さな灯り。
        let led = CGRect(x: rect.maxX - 52, y: rect.midY - 9, width: 18, height: 18)
        ctx.setFillColor(i == 1 ? color(0xFF8A3D) : color(0x0B1530, 0.45))
        ctx.fillEllipse(in: led)
    }
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / size, y: CGFloat(pixels) / size)
    draw(ctx)
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(pixels: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(pixels: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let resources = root.appendingPathComponent("Resources")
try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try! png(pixels: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
print(resources.appendingPathComponent("AppIcon.icns").path)
