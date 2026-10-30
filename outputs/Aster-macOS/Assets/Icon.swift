import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 512
    NSGraphicsContext.current?.imageInterpolation = .high
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    // Aster: a white body with dark eyes and a luminous lavender ring, on a near-black tile.
    let lavender = NSColor(srgbRed: 0.686, green: 0.663, blue: 0.925, alpha: 1)
    let tile = NSBezierPath(roundedRect: NSRect(x: 14, y: 14, width: 484, height: 484), xRadius: 108, yRadius: 108)
    NSGradient(starting: NSColor(srgbRed: 0.055, green: 0.055, blue: 0.067, alpha: 1), ending: NSColor(srgbRed: 0.11, green: 0.106, blue: 0.137, alpha: 1))!.draw(in: tile, angle: 90)
    NSColor(white: 1, alpha: 0.10).setStroke(); tile.lineWidth = 2; tile.stroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: 130, y: 104, width: 252, height: 52))
    lavender.withAlphaComponent(0.18).setStroke(); ring.lineWidth = 34; ring.stroke()
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow(); glow.shadowColor = lavender.withAlphaComponent(0.9); glow.shadowBlurRadius = 22; glow.shadowOffset = .zero; glow.set()
    lavender.setStroke(); ring.lineWidth = 11; ring.stroke()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.5); shadow.shadowBlurRadius = 26; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
    let body = NSBezierPath(roundedRect: NSRect(x: 136, y: 196, width: 240, height: 216), xRadius: 91, yRadius: 91)
    NSGradient(starting: NSColor(srgbRed: 0.937, green: 0.933, blue: 0.984, alpha: 1), ending: .white)!.draw(in: body, angle: 90)
    NSGraphicsContext.restoreGraphicsState()
    lavender.setStroke(); body.lineWidth = 3; body.stroke()
    NSColor(srgbRed: 0.118, green: 0.106, blue: 0.227, alpha: 1).setFill()
    for x in [203.0, 287.0] { NSBezierPath(roundedRect: NSRect(x: x, y: 286, width: 22, height: 42), xRadius: 11, yRadius: 11).fill() }
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try png.write(to: output.appendingPathComponent(name)) }
}
