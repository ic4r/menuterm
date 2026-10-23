import AppKit

/// Draws the app icon in code (dark rounded square + SF Symbol "terminal"), so the bundle
/// needs no artwork checked in. Used at runtime for NSApp.applicationIconImage (alerts, Dock)
/// and by `MenuTerm --write-iconset <dir>` from Scripts/build-app.sh to produce AppIcon.icns.
enum AppIcon {
    static func image(pointSize: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: false) { rect in
            draw(in: rect)
            return true
        }
    }

    private static func draw(in rect: NSRect) {
        // Apple's icon grid: the rounded square sits inside ~10% transparent padding.
        let square = rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1)
        let radius = square.width * 0.2237
        let shape = NSBezierPath(roundedRect: square, xRadius: radius, yRadius: radius)
        let top = NSColor(calibratedRed: 0.24, green: 0.26, blue: 0.30, alpha: 1)
        let bottom = NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.15, alpha: 1)
        NSGradient(starting: top, ending: bottom)?.draw(in: shape, angle: -90)

        let config = NSImage.SymbolConfiguration(pointSize: square.width * 0.46, weight: .medium)
            .applying(.init(paletteColors: [NSColor(calibratedRed: 0.55, green: 0.95, blue: 0.65, alpha: 1)]))
        if let symbol = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let size = symbol.size
            let origin = NSPoint(x: square.midX - size.width / 2, y: square.midY - size.height / 2)
            symbol.draw(in: NSRect(origin: origin, size: size))
        } else {
            // Fallback when the symbol is unavailable: a monospaced prompt.
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: square.width * 0.42, weight: .bold),
                .foregroundColor: NSColor(calibratedRed: 0.55, green: 0.95, blue: 0.65, alpha: 1),
            ]
            let text = ">_" as NSString
            let size = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: square.midX - size.width / 2, y: square.midY - size.height / 2), withAttributes: attrs)
        }
    }

    /// Renders a PNG with exactly `pixels` × `pixels` pixels.
    private static func png(pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = ctx
        draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        ctx.flushGraphics()
        return rep.representation(using: .png, properties: [:])
    }

    /// Writes an .iconset folder that `iconutil -c icns` accepts.
    static func writeIconset(to directory: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                guard let data = png(pixels: base * scale) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
            }
        }
    }
}
