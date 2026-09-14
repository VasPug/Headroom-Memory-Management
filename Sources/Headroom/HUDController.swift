import AppKit
import HeadroomCore

/// Owns the floating panel and its three states. The state machine is the
/// product: ambient until it matters, interrupting once when it does, and
/// fully open only when you ask.
@MainActor
final class HUDController: NSObject {
    private let engine: Engine
    private var geometry = NotchGeometry.current()
    private let panel: NSPanel
    private let content: NotchContentView

    private var mode: HUDMode = .collapsed
    /// Set when you open the panel yourself; it then stays until you close it.
    private var pinned = false
    private var outsideTicks = 0
    private var notificationDeadline = Date.distantFuture
    private var dragging = false

    private var hoverTimer: Timer?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var signalSource: DispatchSourceSignal?

    /// How long a notification waits before withdrawing on its own.
    private let notificationLife: TimeInterval = 9

    /// Exponential ease-out: fast commit, long settle. The one authored moment.
    private let curve = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)

    init(engine: Engine) {
        self.engine = engine
        content = NotchContentView(geometry: geometry, reading: engine.reading)

        panel = NSPanel(
            contentRect: geometry.collapsedFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = content

        super.init()

        content.geometry = geometry
        content.onQuit = { [weak self] in self?.handleQuit($0) }
        content.onKeep = { [weak self] in self?.handleKeep($0) }
        content.onClose = { [weak self] in self?.dismiss() }
        content.onDragBegan = { [weak self] in self?.beginDrag() }
        content.onDragMoved = { [weak self] in self?.moveDrag(by: $0) }
        content.onDragEnded = { [weak self] in self?.dragging = false }
        content.onClick = { [weak self] in self?.handleClick() }
        content.onRightClick = { [weak self] event in
            guard let self else { return }
            NSMenu.popUpContextMenu(self.makeMenu(), with: event, for: self.content)
        }

        engine.onUpdate = { [weak self] in self?.refresh() }
        engine.onNudge = { [weak self] in self?.notify() }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    func show() {
        panel.setFrame(frame(for: .collapsed), display: true)
        panel.orderFrontRegardless()
        refresh()

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        // Clicking anywhere else dismisses the panel. Mouse monitoring needs no
        // permission prompt, unlike watching the keyboard globally.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.mode != .collapsed else { return }
                if !self.panel.frame.contains(NSEvent.mouseLocation) { self.dismiss() }
            }
        }

        // First run: open once so the pill is findable. Nothing explains where
        // a 92-point pill lives better than showing it.
        if !Settings.hasLaunchedBefore {
            Settings.hasLaunchedBefore = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.mode == .collapsed else { return }
                    self.pinned = true
                    self.setMode(.expanded)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                MainActor.assumeIsolated { self?.dismiss() }
            }
        }

        // `kill -USR1 <pid>` replays the recommendation, so the notification can
        // be checked without waiting for the machine to actually run low.
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.notify(force: true) }
        }
        source.resume()
        signalSource = source


        // Esc closes whenever our own panel holds the key window.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, event.keyCode == 53, self.mode != .collapsed else { return event }
            MainActor.assumeIsolated { self.dismiss() }
            return nil
        }
    }

    // MARK: - Mode transitions

    private func frame(for mode: HUDMode) -> CGRect {
        mode == .collapsed
            ? geometry.collapsedFrame()
            : geometry.expandedFrame(contentHeight: content.contentHeight, width: mode.panelWidth)
    }

    private func setMode(_ new: HUDMode, animated: Bool = true) {
        guard new != mode else { return }
        let opening = mode == .collapsed
        mode = new
        content.mode = new
        outsideTicks = 0

        content.needsLayout = true
        content.layoutSubtreeIfNeeded()
        let target = frame(for: new)
        panel.hasShadow = new != .collapsed

        if opening {
            // Content arrives just behind the shape, so it reads as the panel
            // opening rather than as a list appearing.
            for sub in content.subviews where !sub.isHidden { sub.alphaValue = 0 }
        }

        guard animated else {
            panel.setFrame(target, display: true)
            content.needsDisplay = true
            return
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = new == .collapsed ? 0.26 : 0.32
            ctx.timingFunction = curve
            panel.animator().setFrame(target, display: true)
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = curve
            for sub in content.subviews where !sub.isHidden { sub.animator().alphaValue = 1 }
        }
        content.needsDisplay = true
    }

    private func dismiss() {
        pinned = false
        notificationDeadline = .distantFuture
        setMode(.collapsed)
    }

    /// Pressure just turned bad. Say one thing, not five.
    private func notify(force: Bool = false) {
        if force, mode != .collapsed { dismiss() }
        guard mode == .collapsed, engine.ranked.first != nil else { return }
        notificationDeadline = Date().addingTimeInterval(notificationLife)
        setMode(.notification)
    }

    private func handleClick() {
        switch mode {
        case .collapsed, .notification:
            pinned = true
            notificationDeadline = .distantFuture
            setMode(.expanded)
        case .expanded:
            pinned.toggle()
        }
    }

    /// Shrink to the pill first, so what you drag is what you are placing.
    private func beginDrag() {
        dragging = true
        pinned = false
        notificationDeadline = .distantFuture
        setMode(.collapsed, animated: false)
    }

    private func moveDrag(by dx: CGFloat) {
        var frame = panel.frame
        frame.origin.x = geometry.clampX(frame.origin.x + dx, width: frame.width)
        panel.setFrameOrigin(frame.origin)
        Settings.pillX = frame.origin.x
    }

    private func tick() {
        guard !dragging else { return }
        let inside = panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
        switch mode {
        case .collapsed:
            if inside { setMode(.expanded) }
        case .notification:
            // Reading it keeps it up; walking away lets it go.
            if inside {
                notificationDeadline = Date().addingTimeInterval(4)
            } else if Date() > notificationDeadline {
                setMode(.collapsed)
            }
        case .expanded:
            guard !pinned else { return }
            outsideTicks = inside ? 0 : outsideTicks + 1
            if outsideTicks >= 2 { dismiss() }   // ~0.36s of grace
        }
    }

    // MARK: - Data

    private func refresh() {
        content.reading = engine.reading
        content.items = engine.ranked
        content.rebuild()
        if mode != .collapsed { resizeToContent() }
        content.needsDisplay = true
    }

    private func resizeToContent() {
        let target = frame(for: mode)
        guard target != panel.frame else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = curve
            panel.animator().setFrame(target, display: true)
        }
    }

    private func handleQuit(_ item: RankedCandidate) {
        let fromNotification = mode == .notification
        engine.quit(item)
        if fromNotification {
            dismiss()
        } else {
            pinned = true   // keep the panel open so you can quit several in a row
        }
    }

    private func handleKeep(_ item: RankedCandidate) {
        pinned = true
        engine.protect(item)
    }

    private func screensChanged() {
        geometry = NotchGeometry.current()
        content.geometry = geometry
        panel.setFrame(frame(for: mode), display: true)
        content.needsDisplay = true
    }

    // MARK: - Context menu

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Rescan now", action: #selector(rescan), keyEquivalent: "").target = self
        let side = NSMenuItem(title: Settings.side == "right" ? "Move to left of notch" : "Move to right of notch",
                              action: #selector(flipSide), keyEquivalent: "")
        side.target = self
        menu.addItem(side)

        let kept = Settings.protectedIDs
        if !kept.isEmpty {
            let item = NSMenuItem(title: "Stop keeping \(kept.count) app\(kept.count == 1 ? "" : "s")",
                                  action: #selector(clearProtected), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Erase learned usage", action: #selector(eraseUsage), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Headroom", action: #selector(quitApp), keyEquivalent: "q").target = self
        return menu
    }

    @objc private func rescan() { engine.rescan() }
    @objc private func clearProtected() { Settings.protectedIDs = []; engine.rescan() }
    @objc private func flipSide() {
        Settings.side = Settings.side == "right" ? "left" : "right"
        Settings.pillX = nil   // the side toggle overrides a dragged position
        if mode == .collapsed { panel.setFrame(geometry.collapsedFrame(), display: true) }
    }

    @objc private func eraseUsage() {
        engine.usage.erase()
        engine.rescan()
    }
    @objc private func quitApp() {
        engine.usage.flush()
        NSApp.terminate(nil)
    }
}
