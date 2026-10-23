import AppKit

/// Custom menu row for one session: title + CPU/MEM on the first line, the last output lines
/// (up to `maxLines`) below, a translucent tint by memory rank behind it, and a chevron for the submenu.
/// Being a view (not a plain NSMenuItem) also lets a click open the session even though the
/// item carries a submenu — AppKit never fires the action of a plain item that has one.
final class SessionMenuRow: NSView {
    struct Model: Equatable {
        var symbol: String
        var name: String
        /// Last terminal lines, oldest first (at most `maxLines`).
        var lines: [String]
        var stats: String?
        /// Fill color (already translucent) or nil for no tint.
        var tint: NSColor?
    }

    static let preferredWidth: CGFloat = 400
    static let maxLines = 3
    static let titleHeight: CGFloat = 20
    static let lineHeight: CGFloat = 15
    static let preferredHeight: CGFloat = 10 + titleHeight + lineHeight * CGFloat(maxLines) + 10

    var model: Model { didSet { if model != oldValue { needsDisplay = true } } }
    private let onClick: () -> Void
    private var hovered = false { didSet { if hovered != oldValue { needsDisplay = true } } }

    init(model: Model, onClick: @escaping () -> Void) {
        self.model = model
        self.onClick = onClick
        super.init(frame: NSRect(x: 0, y: 0, width: Self.preferredWidth, height: Self.preferredHeight))
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.preferredWidth, height: Self.preferredHeight) }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        let action = onClick
        DispatchQueue.main.async(execute: action)
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = hovered || (enclosingMenuItem?.isHighlighted ?? false)
        let cell = NSRect(x: 5, y: 2, width: bounds.width - 10, height: bounds.height - 4)
        let path = NSBezierPath(roundedRect: cell, xRadius: 5, yRadius: 5)
        if let tint = model.tint {
            tint.setFill()
            path.fill()
        }
        if highlighted {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(model.tint == nil ? 1 : 0.75).setFill()
            path.fill()
        }

        let primary: NSColor = highlighted ? .selectedMenuItemTextColor : .labelColor
        let secondary: NSColor = highlighted ? NSColor.selectedMenuItemTextColor.withAlphaComponent(0.8) : .secondaryLabelColor
        let left = cell.minX + 9
        let chevronWidth: CGFloat = 16
        let right = cell.maxX - chevronWidth - 4

        // Chevron for the submenu (AppKit does not draw one for view-based items).
        let chevronAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: secondary]
        let chevron = "▸" as NSString
        let chevronSize = chevron.size(withAttributes: chevronAttrs)
        chevron.draw(at: NSPoint(x: cell.maxX - chevronWidth + (chevronWidth - chevronSize.width) / 2,
                                 y: cell.midY - chevronSize.height / 2), withAttributes: chevronAttrs)

        // First line: symbol + name on the left, stats on the right.
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: primary]
        let statsAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular), .foregroundColor: secondary,
        ]
        let titleY = cell.maxY - 6 - Self.titleHeight
        var statsWidth: CGFloat = 0
        if let stats = model.stats {
            let size = stats.size(withAttributes: statsAttrs)
            statsWidth = size.width + 8
            stats.draw(at: NSPoint(x: right - size.width, y: titleY + 1), withAttributes: statsAttrs)
        }
        let title = "\(model.symbol) \(model.name)"
        truncated(title, attrs: titleAttrs).draw(in: NSRect(x: left, y: titleY, width: right - left - statsWidth, height: 17))

        // Output lines below the title, oldest first, each truncated to the row.
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular), .foregroundColor: secondary,
        ]
        var y = titleY - 2
        for line in model.lines.suffix(Self.maxLines) {
            y -= Self.lineHeight
            truncated(line, attrs: subAttrs).draw(in: NSRect(x: left + 4, y: y, width: right - left - 4, height: Self.lineHeight))
        }
    }

    private func truncated(_ text: String, attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        var a = attrs
        a[.paragraphStyle] = style
        return NSAttributedString(string: text, attributes: a)
    }

    /// Rank-based tint: 0 = heaviest (red) … 1 = lightest (green). Translucent so it reads as a wash.
    static func tint(rank: Int, of count: Int) -> NSColor {
        let fraction = count > 1 ? Double(rank) / Double(count - 1) : 1
        return NSColor(hue: 0.33 * fraction, saturation: 0.85, brightness: 0.95, alpha: 0.22)
    }
}
