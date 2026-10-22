import AppKit

/// Menu row split into two clickable halves (left: Quick Command, right: New Session).
final class SplitMenuRow: NSView {
    private struct Half {
        let title: String
        let action: () -> Void
    }

    private let halves: [Half]
    private var hovered: Int? { didSet { if hovered != oldValue { needsDisplay = true } } }

    init(left: (String, () -> Void), right: (String, () -> Void)) {
        halves = [Half(title: left.0, action: left.1), Half(title: right.0, action: right.1)]
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: 300, height: 30) }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    private func index(at point: NSPoint) -> Int? {
        guard bounds.contains(point) else { return nil }
        return point.x < bounds.midX ? 0 : 1
    }

    override func mouseMoved(with event: NSEvent) { hovered = index(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { hovered = index(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func mouseUp(with event: NSEvent) {
        guard let i = index(at: convert(event.locationInWindow, from: nil)) else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        let action = halves[i].action
        DispatchQueue.main.async(execute: action)
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 5
        let half = (bounds.width - inset * 2) / 2
        for (i, h) in halves.enumerated() {
            let rect = NSRect(x: inset + CGFloat(i) * half, y: 2, width: half, height: bounds.height - 4)
            let isHover = hovered == i
            if isHover {
                NSColor.selectedContentBackgroundColor.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 0), xRadius: 5, yRadius: 5).fill()
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: isHover ? NSColor.selectedMenuItemTextColor : NSColor.labelColor,
            ]
            let size = h.title.size(withAttributes: attrs)
            h.title.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
        }
        // Divider between the halves.
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.midX - 0.5, y: 7, width: 1, height: bounds.height - 14).fill()
    }
}
