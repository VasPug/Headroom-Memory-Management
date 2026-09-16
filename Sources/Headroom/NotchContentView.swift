import AppKit
import HeadroomCore

/// Draws the HUD. Collapsed it is a pill beside the notch; expanded it is a
/// panel that hangs off the notch's bottom edge, cut from a single path so the
/// two read as one piece of hardware.
final class NotchContentView: NSView {
    var geometry: NotchGeometry
    var reading: PressureReading
    var items: [RankedCandidate] = []
    var mode: HUDMode = .collapsed
    /// The single recommendation the notification is making.
    var featured: RankedCandidate? { items.first }

    var onQuit: ((RankedCandidate) -> Void)?
    var onKeep: ((RankedCandidate) -> Void)?
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onClose: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?

    private var rowViews: [RowView] = []

    private lazy var closeButton = PillButton(title: "Close") { [weak self] in self?.onClose?() }
    private lazy var notificationQuit = PillButton(title: "Quit", destructive: true) { [weak self] in
        guard let self, let item = self.featured else { return }
        self.onQuit?(item)
    }
    private var notificationIcon: NSImage?

    static let maxRows = 5
    private let headerTopPad: CGFloat = 16
    private let headerBottomPad: CGFloat = 14
    private let barHeight: CGFloat = 5
    private let footerHeight: CGFloat = 34
    private let sidePad: CGFloat = 20

    init(geometry: NotchGeometry, reading: PressureReading) {
        self.geometry = geometry
        self.reading = reading
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    // MARK: - Measurement

    var visibleItems: [RankedCandidate] { Array(items.prefix(Self.maxRows)) }

    private var headerHeight: CGFloat {
        var h = headerTopPad + 18 + 12 + barHeight + headerBottomPad
        if reading.sample.swapUsedBytes > 0 { h += 20 }
        return h
    }

    private var listHeight: CGFloat {
        visibleItems.isEmpty ? 62 : CGFloat(visibleItems.count) * RowView.height
    }

    static let notificationHeight: CGFloat = 78

    var contentHeight: CGFloat {
        switch mode {
        case .collapsed: return 0
        case .notification: return Self.notificationHeight
        case .expanded: return headerHeight + listHeight + footerHeight
        }
    }

    // MARK: - Rows

    func rebuild() {
        notificationIcon = featured.flatMap { NSRunningApplication(processIdentifier: $0.candidate.pid)?.icon }
        if closeButton.superview == nil { addSubview(closeButton) }
        if notificationQuit.superview == nil { addSubview(notificationQuit) }

        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = visibleItems.map { item in
            RowView(
                item: item,
                onQuit: { [weak self] in self?.onQuit?($0) },
                onKeep: { [weak self] in self?.onKeep?($0) }
            )
        }
        rowViews.forEach(addSubview)
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()

        let listVisible = mode == .expanded
        var y = geometry.stripHeight + headerHeight
        for row in rowViews {
            row.isHidden = !listVisible
            row.frame = NSRect(x: 0, y: y, width: bounds.width, height: RowView.height)
            y += RowView.height
        }

        closeButton.isHidden = mode != .expanded
        let closeW = closeButton.intrinsicWidth
        closeButton.frame = NSRect(x: bounds.width - sidePad + 4 - closeW,
                                   y: bounds.height - footerHeight + 5,
                                   width: closeW, height: 24)

        notificationQuit.isHidden = mode != .notification || featured == nil
        let quitW = notificationQuit.intrinsicWidth
        notificationQuit.frame = NSRect(x: bounds.width - 18 - quitW,
                                        y: geometry.stripHeight + (Self.notificationHeight - 26) / 2,
                                        width: quitW, height: 26)
    }

    // MARK: - Input

    /// The panel never becomes key, so without this the first click on it is
    /// swallowed by the window system instead of reaching the control.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var dragging = false
    /// The pill opens on click, so it has to look like it can be clicked.
    private var hoveringPill = false { didSet { if mode == .collapsed { needsDisplay = true } } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hoveringPill = true }
    override func mouseExited(with event: NSEvent) { hoveringPill = false }

    override func mouseDown(with event: NSEvent) {
        // Command-drag repositions the pill, the same gesture macOS uses for
        // rearranging menu bar items.
        if event.modifierFlags.contains(.command) {
            dragging = true
            onDragBegan?()
            return
        }
        onClick?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        onDragMoved?(event.deltaX)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        onDragEnded?()
    }
    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.setShouldAntialias(true)
        switch mode {
        case .collapsed: drawCollapsed()
        case .notification: drawNotification()
        case .expanded: drawExpanded()
        }
    }

    // The pill beside the notch.
    /// The bar fills as memory is consumed, the way every storage and battery
    /// meter does: nearly full and red means nearly out. Draining it instead --
    /// so it tracked the "GB free" number -- made a red bar look almost empty,
    /// which read as "barely any problem" at exactly the wrong moment.
    private var filled: CGFloat { CGFloat(max(0, min(1, reading.score))) }

    private func drawCollapsed() {
        let pill = NSRect(x: 0, y: (bounds.height - 22) / 2, width: bounds.width, height: 22)
        NSColor(white: 1, alpha: hoveringPill ? 0.16 : 0.08).setFill()
        let path = NSBezierPath(roundedRect: pill, xRadius: 11, yRadius: 11)
        path.fill()
        Palette.hairline.setStroke()
        path.lineWidth = 1
        path.stroke()

        let level = Palette.color(for: reading.level)
        let track = NSRect(x: pill.minX + 10, y: pill.midY - 2.5, width: 26, height: 5)
        Palette.track.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()
        level.setFill()
        let fillWidth = max(3, track.width * filled)
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: fillWidth, height: track.height),
                     xRadius: 2.5, yRadius: 2.5).fill()

        let free = Fmt.gb(reading.sample.availableBytes) as NSString
        free.draw(at: NSPoint(x: track.maxX + 8, y: pill.midY - 6.5), withAttributes: [
            .font: Type.number(11, .medium),
            .foregroundColor: Palette.primary,
        ])
    }

    /// One recommendation, sized so it reads in a glance without covering work.
    private func drawNotification() {
        shellPath().addClip()
        Palette.shell.setFill()
        bounds.fill()
        let outline = shellPath()
        outline.lineWidth = 1
        Palette.hairline.setStroke()
        outline.stroke()

        guard let item = featured else { return }
        let top = geometry.stripHeight
        let level = Palette.color(for: reading.level)

        let iconRect = NSRect(x: 18, y: top + (Self.notificationHeight - 30) / 2, width: 30, height: 30)
        if let notificationIcon {
            notificationIcon.draw(in: iconRect)
        } else {
            Palette.tertiary.setFill()
            NSBezierPath(ovalIn: iconRect.insetBy(dx: 9, dy: 9)).fill()
        }

        let textX: CGFloat = 60
        let headline = "Quit \(item.candidate.name)?" as NSString
        headline.draw(at: NSPoint(x: textX, y: top + 18), withAttributes: [
            .font: Type.text(13.5, .semibold),
            .foregroundColor: Palette.primary,
        ])

        // The amount you get back carries the pressure color, because that is
        // the number the color is about.
        let subY = top + 38
        let gain = "Frees \(Fmt.size(item.candidate.memoryBytes))" as NSString
        let gainAttrs: [NSAttributedString.Key: Any] = [
            .font: Type.number(11, .semibold), .foregroundColor: level,
        ]
        gain.draw(at: NSPoint(x: textX, y: subY), withAttributes: gainAttrs)

        let rest = max(0, items.count - 1)
        var tail = ""
        if item.candidate.kind == .app {
            tail += "  ·  \(Fmt.idle(item.idle, known: item.candidate.lastUsed != nil))"
        }
        tail += rest > 0 ? "  ·  \(rest) more" : "  ·  click for details"
        (tail as NSString).draw(at: NSPoint(x: textX + gain.size(withAttributes: gainAttrs).width, y: subY),
                                withAttributes: [
            .font: Type.number(11, .regular),
            .foregroundColor: Palette.secondary,
        ])
    }

    private func drawExpanded() {
        shellPath().addClip()
        Palette.shell.setFill()
        bounds.fill()

        // Hairline along the panel's outer edge only, so elevation is declared
        // once: the shadow lifts it, the hairline defines it.
        let outline = shellPath()
        outline.lineWidth = 1
        Palette.hairline.setStroke()
        outline.stroke()

        drawHeader()
        if visibleItems.isEmpty { drawEmptyState() }
        drawFooter()
    }

    /// One continuous outline: down the notch's sides, flaring out into the
    /// panel below it.
    private func shellPath() -> NSBezierPath {
        let W = bounds.width, H = bounds.height, S = geometry.stripHeight
        // The notch is fixed in screen space; the view is not. Live, the content
        // view sits at the window origin, so the window's position is what maps
        // screen coordinates into this view. (The offscreen renderer has no
        // window and positions the view itself.)
        let originX = window?.frame.minX ?? frame.minX
        let nl = geometry.notchRect.minX - originX
        let nr = geometry.notchRect.maxX - originX
        let flare: CGFloat = 12   // concave corner where notch meets panel
        let topR: CGFloat = 10
        let botR: CGFloat = 16

        // Mid-animation the panel can be too narrow to reach the notch. Drop the
        // cutout rather than drawing a broken outline; it settles into place as
        // the panel finishes opening.
        guard nl > topR + flare, nr < W - topR - flare else {
            return NSBezierPath(roundedRect: NSRect(x: 0, y: S, width: W, height: max(0, H - S)),
                                xRadius: botR, yRadius: botR)
        }

        let p = NSBezierPath()
        p.move(to: NSPoint(x: nl, y: 0))
        p.line(to: NSPoint(x: nl, y: S - flare))
        p.curve(to: NSPoint(x: nl - flare, y: S),
                controlPoint1: NSPoint(x: nl, y: S), controlPoint2: NSPoint(x: nl, y: S))
        p.line(to: NSPoint(x: topR, y: S))
        p.curve(to: NSPoint(x: 0, y: S + topR),
                controlPoint1: NSPoint(x: 0, y: S), controlPoint2: NSPoint(x: 0, y: S))
        p.line(to: NSPoint(x: 0, y: H - botR))
        p.curve(to: NSPoint(x: botR, y: H),
                controlPoint1: NSPoint(x: 0, y: H), controlPoint2: NSPoint(x: 0, y: H))
        p.line(to: NSPoint(x: W - botR, y: H))
        p.curve(to: NSPoint(x: W, y: H - botR),
                controlPoint1: NSPoint(x: W, y: H), controlPoint2: NSPoint(x: W, y: H))
        p.line(to: NSPoint(x: W, y: S + topR))
        p.curve(to: NSPoint(x: W - topR, y: S),
                controlPoint1: NSPoint(x: W, y: S), controlPoint2: NSPoint(x: W, y: S))
        p.line(to: NSPoint(x: nr + flare, y: S))
        p.curve(to: NSPoint(x: nr, y: S - flare),
                controlPoint1: NSPoint(x: nr, y: S), controlPoint2: NSPoint(x: nr, y: S))
        p.line(to: NSPoint(x: nr, y: 0))
        p.close()
        return p
    }

    private func drawHeader() {
        let S = geometry.stripHeight
        let level = Palette.color(for: reading.level)
        var y = S + headerTopPad

        (Palette.headline(for: reading.level) as NSString).draw(at: NSPoint(x: sidePad, y: y), withAttributes: [
            .font: Type.text(15, .semibold),
            .foregroundColor: Palette.primary,
        ])

        let right = "\(Fmt.gb(reading.sample.availableBytes)) free" as NSString
        let rightAttrs: [NSAttributedString.Key: Any] = [
            .font: Type.number(12.5, .medium),
            .foregroundColor: level,
        ]
        let rightSize = right.size(withAttributes: rightAttrs)
        right.draw(at: NSPoint(x: bounds.width - sidePad - rightSize.width, y: y + 2), withAttributes: rightAttrs)

        y += 18 + 12
        let track = NSRect(x: sidePad, y: y, width: bounds.width - sidePad * 2, height: barHeight)
        Palette.track.setFill()
        NSBezierPath(roundedRect: track, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        level.setFill()
        let w = max(barHeight, track.width * filled)
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: w, height: track.height),
                     xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

        if reading.sample.swapUsedBytes > 0 {
            y += barHeight + 9
            // The signal macOS keeps to itself until the machine is already slow.
            let swap = "\(Fmt.size(reading.sample.swapUsedBytes)) swapped to disk" as NSString
            swap.draw(at: NSPoint(x: sidePad, y: y), withAttributes: [
                .font: Type.number(11, .regular),
                .foregroundColor: Palette.warn,
            ])
        }

        Palette.hairline.setFill()
        NSRect(x: 0, y: S + headerHeight - 0.5, width: bounds.width, height: 0.5).fill()
    }

    private func drawEmptyState() {
        let top = geometry.stripHeight + headerHeight
        let line = "Nothing worth quitting" as NSString
        line.draw(at: NSPoint(x: sidePad, y: top + 14), withAttributes: [
            .font: Type.text(13, .medium),
            .foregroundColor: Palette.primary,
        ])
        let sub = "Everything open is either in use or too small to matter." as NSString
        sub.draw(at: NSPoint(x: sidePad, y: top + 33), withAttributes: [
            .font: Type.text(11, .regular),
            .foregroundColor: Palette.secondary,
        ])
    }

    private func drawFooter() {
        let top = bounds.height - footerHeight
        Palette.hairline.setFill()
        NSRect(x: 0, y: top, width: bounds.width, height: 0.5).fill()

        // Says the thing the user is actually afraid of, up front.
        let note = "Graceful quit — unsaved work still prompts." as NSString
        note.draw(at: NSPoint(x: sidePad, y: top + 11), withAttributes: [
            .font: Type.text(11, .regular),
            .foregroundColor: Palette.tertiary,
        ])
    }
}
