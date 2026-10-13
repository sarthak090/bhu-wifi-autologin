// Renders the app icon into an .iconset folder: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let purple = NSColor(red: 0.29, green: 0.16, blue: 0.47, alpha: 1)
let deepPurple = NSColor(red: 0.16, green: 0.08, blue: 0.29, alpha: 1)
let orange = NSColor(red: 0.95, green: 0.52, blue: 0.16, alpha: 1)

func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
}

func drawCentered(_ image: NSImage, at center: NSPoint) {
    let s = image.size
    image.draw(in: NSRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height))
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(px)
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(starting: purple, ending: deepPurple)!.draw(in: tilePath, angle: -90)

    if let cap = symbol("graduationcap.fill", size: s * 0.34, color: .white) {
        drawCentered(cap, at: NSPoint(x: s * 0.5, y: s * 0.53))
    }

    // Orange Wi-Fi badge, bottom right.
    let badgeCenter = NSPoint(x: s * 0.72, y: s * 0.28)
    let r = s * 0.13
    orange.setFill()
    NSBezierPath(ovalIn: NSRect(x: badgeCenter.x - r, y: badgeCenter.y - r, width: 2 * r, height: 2 * r)).fill()
    if let wifi = symbol("wifi", size: s * 0.11, color: .white) {
        drawCentered(wifi, at: badgeCenter)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]
for (name, px) in sizes {
    try render(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
