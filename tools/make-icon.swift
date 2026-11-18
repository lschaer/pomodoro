// Generates Resources/AppIcon.icns: a graphite rounded square with the 12-dot ring,
// nine dots lit — the same ring the menu bar shows while a session runs.
// Usage: swift tools/make-icon.swift <output-dir>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024           // design on a 1024 grid

    // Body: macOS icon grid (824pt square, ~185pt corner radius), with a soft drop shadow.
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor(white: 0.12, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(white: 0.22, alpha: 1), ending: NSColor(white: 0.10, alpha: 1))!
        .draw(in: shape, angle: -90)

    // Ring of 12 dots, clockwise from the top; the last three are dim.
    let center = CGPoint(x: 512 * s, y: 512 * s)
    let radius = 270 * s, dot = 42 * s
    for i in 0..<12 {
        let angle = CGFloat.pi / 2 - CGFloat(i) * 2 * .pi / 12
        let p = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        NSColor.white.withAlphaComponent(i < 9 ? 0.95 : 0.18).setFill()
        NSBezierPath(ovalIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(pixels: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(pixels: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("Wrote \(outDir.appendingPathComponent("AppIcon.icns").path)")
