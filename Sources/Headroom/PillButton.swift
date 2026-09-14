import AppKit

/// A small pill control. `destructive` shifts it toward red on hover, so the
/// consequence shows up at the moment of intent rather than in a dialog after.
final class PillButton: NSView {
    var title: String { didSet { needsDisplay = true } }
    var destructive: Bool
    var action: () -> Void

    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }

    init(title: String, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.destructive = destructive
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false; pressed = false }
    /// The panel never becomes key, so without this the first click on it is
    /// swallowed by the window system instead of reaching the control.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { pressed = true }

    override func mouseUp(with event: NSEvent) {
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }

    var intrinsicWidth: CGFloat {
        let size = (title as NSString).size(withAttributes: [.font: Type.text(11.5, .semibold)])
        return ceil(size.width) + 22
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)

        let fill: NSColor
        let ink: NSColor
        if destructive && hovering {
            fill = Palette.critical.withAlphaComponent(pressed ? 0.38 : 0.26)
            ink = NSColor(srgbRed: 1, green: 0.62, blue: 0.58, alpha: 1)
        } else if hovering {
            fill = NSColor(white: 1, alpha: pressed ? 0.22 : 0.16)
            ink = Palette.primary
        } else {
            fill = NSColor(white: 1, alpha: 0.09)
            ink = NSColor(white: 0.82, alpha: 1)
        }

        fill.setFill()
        path.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: Type.text(11.5, .semibold),
            .foregroundColor: ink,
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                              y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}
