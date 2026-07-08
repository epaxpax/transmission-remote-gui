// Transmission Remote GUI app icon generator.
//
// Renders the dock-icon motif (blue disc + white bird = transfer/messenger, in the spirit
// of Transmission, drawn ourselves from Apple's `bird.fill` SF Symbol) at every size of a
// macOS `.iconset`; `build-app.sh` then turns it into an `.icns` with `iconutil`.
//
// Usage:  swift Scripts/make-icon.swift <output .iconset directory>

import AppKit

let light = NSColor(calibratedRed: 0.32, green: 0.74, blue: 0.97, alpha: 1)
let dark  = NSColor(calibratedRed: 0.09, green: 0.44, blue: 0.78, alpha: 1)

/// Draws the whole icon at the given pixel size into a bitmap rep.
func renderIcon(px: Int) -> NSBitmapImageRep {
    let s = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("Failed to create bitmap rep (\(px)px)") }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    // Blue disc with a radial gradient (matching the dockIcon's 18px inset at 512px).
    let disc = NSBezierPath(ovalIn: rect.insetBy(dx: s * 0.035, dy: s * 0.035))
    NSGradient(colors: [light, dark])?.draw(in: disc, relativeCenterPosition: NSPoint(x: -0.15, y: 0.35))

    // White bird (SF Symbol) centered, ~48% of the width.
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.48, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let bird = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let sz = bird.size
        bird.draw(in: NSRect(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2,
                             width: sz.width, height: sz.height))
    }
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed: \(path)")
    }
    do { try data.write(to: URL(fileURLWithPath: path)) }
    catch { fatalError("Write failed (\(path)): \(error)") }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("Usage: make-icon.swift <.iconset directory>\n".data(using: .utf8)!)
    exit(2)
}
let outDir = CommandLine.arguments[1]

// Files required by the .iconset (name → pixel size). Identical sizes are cached.
let entries: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),   ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),   ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),("icon_512x512@2x.png", 1024),
]

var cache: [Int: NSBitmapImageRep] = [:]
for (name, px) in entries {
    let rep = cache[px] ?? renderIcon(px: px)
    cache[px] = rep
    writePNG(rep, to: "\(outDir)/\(name)")
}
print("Icon rendered: \(entries.count) files → \(outDir)")
