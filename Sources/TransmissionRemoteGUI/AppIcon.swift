import AppKit

/// App and menu bar icon drawn in code (there is no .app bundle, so it is set at runtime).
/// Motif: in the spirit of Transmission, a bird (transfer/messenger) on a blue disc —
/// our own drawing based on Apple's `bird.fill` SF Symbol, not a copy of the Transmission logo.
enum AppIcon {
    /// Gradient colors of the disc.
    static let light = NSColor(calibratedRed: 0.32, green: 0.74, blue: 0.97, alpha: 1)
    static let dark  = NSColor(calibratedRed: 0.09, green: 0.44, blue: 0.78, alpha: 1)

    /// Colored Dock icon: blue disc + white bird.
    static func dockIcon() -> NSImage {
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { rect in
            drawDisc(in: rect.insetBy(dx: 18, dy: 18))
            drawBird(in: rect, fraction: 0.48, color: .white)
            return true
        }
    }

    /// Monochrome menu bar icon (template — the system tints it for the light/dark bar).
    static func menuBarIcon() -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: "Transmission Remote GUI")?
            .withSymbolConfiguration(cfg) ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// Blue disc with a radial gradient (light from the upper left).
    private static func drawDisc(in r: NSRect) {
        let disc = NSBezierPath(ovalIn: r)
        NSGradient(colors: [light, dark])?.draw(in: disc, relativeCenterPosition: NSPoint(x: -0.15, y: 0.35))
    }

    /// Draws the `bird.fill` SF Symbol centered in the rect, at the given fraction of its width.
    private static func drawBird(in r: NSRect, fraction: CGFloat, color: NSColor) {
        let cfg = NSImage.SymbolConfiguration(pointSize: r.width * fraction, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let bird = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else { return }
        let sz = bird.size
        bird.draw(in: NSRect(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2, width: sz.width, height: sz.height))
    }
}
