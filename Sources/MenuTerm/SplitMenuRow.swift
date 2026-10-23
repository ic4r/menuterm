import AppKit

/// Button-like menu row split into equal clickable segments (one segment = a full-width button).
/// Used for the top row (Quick Command | New Session) and the favorite-session row.
final class SplitMenuRow: NSView {
    private struct Segment {
        let title: String
        let action: () -> Void
    }

    static let preferredHeight: CGFloat = 44

    private let segments: [Segment]
    private var hovered: Int? { didSet { if hovered != oldValue { needsDisplay = true } } }

    init(segments: [(String, () -> Void)]) {
        self.segments = segments.map { Segment(title: $0.0, action: $0.1) }
        super.init(frame: NSRect(x: 0, y: 0, width: SessionMenuRow.preferredWidth, height: Self.preferredHeight))
        autoresizingMask = [.width]
    }

    convenience init(left: (String, () -> Void), right: (String, () -> Void)) {
        self.init(segments: [left, right])
    }

    convenience init(single title: String, action: @escaping () -> Void) {
        self.init(segments: [(title, action)])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: SessionMenuRow.preferredWidth, height: Self.preferredHeight)
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    private var inset: CGFloat { 5 }
    private var segmentWidth: CGFloat { (bounds.width - inset * 2) / CGFloat(segments.count) }

    private func index(at point: NSPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        let i = Int((point.x - inset) / segmentWidth)
        return min(max(i, 0), segments.count - 1)
    }

    override func mouseMoved(with event: NSEvent) { hovered = index(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { hovered = index(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func mouseUp(with event: NSEvent) {
        guard let i = index(at: convert(event.locationInWindow, from: nil)) else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        let action = segments[i].action
        DispatchQueue.main.async(execute: action)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, seg) in segments.enumerated() {
            let rect = NSRect(x: inset + CGFloat(i) * segmentWidth, y: 3, width: segmentWidth, height: bounds.height - 6)
            let isHover = hovered == i
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 0), xRadius: 6, yRadius: 6)
            // Resting state reads as a button: faint fill so the row stands apart from plain items.
            (isHover ? NSColor.selectedContentBackgroundColor : NSColor.labelColor.withAlphaComponent(0.06)).setFill()
            path.fill()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: isHover ? NSColor.selectedMenuItemTextColor : NSColor.labelColor,
            ]
            let size = seg.title.size(withAttributes: attrs)
            seg.title.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
        }
    }
}
