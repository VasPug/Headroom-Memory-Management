import AppKit
import HeadroomCore

/// One quit candidate: who it is, what it costs you, and how long since you
/// cared about it.
final class RowView: NSView {
    static let height: CGFloat = 50

    let item: RankedCandidate
    private let icon: NSImage?
    private var hovering = false { didSet { needsDisplay = true; updateActions() } }

    private lazy var quitButton = PillButton(title: "Quit", destructive: true) { [weak self] in
        guard let self else { return }
        self.onQuit(self.item)
    }
    private lazy var keepButton = PillButton(title: "Keep") { [weak self] in
        guard let self else { return }
        self.onKeep(self.item)
    }

    let onQuit: (RankedCandidate) -> Void
    let onKeep: (RankedCandidate) -> Void

    init(item: RankedCandidate,
         onQuit: @escaping (RankedCandidate) -> Void,
         onKeep: @escaping (RankedCandidate) -> Void) {
        self.item = item
        self.onQuit = onQuit
        self.onKeep = onKeep
        self.icon = NSRunningApplication(processIdentifier: item.candidate.pid)?.icon
        super.init(frame: .zero)
        addSubview(quitButton)
        addSubview(keepButton)
        keepButton.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let quitW = quitButton.intrinsicWidth
        let keepW = keepButton.intrinsicWidth
        let y = (bounds.height - 24) / 2
        quitButton.frame = NSRect(x: bounds.width - 16 - quitW, y: y, width: quitW, height: 24)
        keepButton.frame = NSRect(x: quitButton.frame.minX - 6 - keepW, y: y, width: keepW, height: 24)
    }

    private func updateActions() {
        keepButton.isHidden = !hovering
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    /// The panel never becomes key, so without this the first click on it is
    /// swallowed by the window system instead of reaching the control.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            Palette.rowHover.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 2), xRadius: 10, yRadius: 10).fill()
        }

        let iconRect = NSRect(x: 16, y: (bounds.height - 26) / 2, width: 26, height: 26)
        if let icon {
            icon.draw(in: iconRect)
        } else {
            // A background process has no icon; a dot in the level color keeps
            // the row's left edge aligned without faking an app identity.
            Palette.tertiary.setFill()
            NSBezierPath(ovalIn: iconRect.insetBy(dx: 8, dy: 8)).fill()
        }

        let textX: CGFloat = 54
        let name = item.candidate.name as NSString
        name.draw(at: NSPoint(x: textX, y: 8), withAttributes: [
            .font: Type.text(13, .medium),
            .foregroundColor: Palette.primary,
        ])

        let detail = item.candidate.kind == .process
            ? "\(Fmt.size(item.candidate.memoryBytes))  ·  background process"
            : "\(Fmt.size(item.candidate.memoryBytes))  ·  \(Fmt.idle(item.idle, known: item.candidate.lastUsed != nil))"
        (detail as NSString).draw(at: NSPoint(x: textX, y: 27), withAttributes: [
            .font: Type.number(11, .regular),
            .foregroundColor: Palette.secondary,
        ])
    }
}
