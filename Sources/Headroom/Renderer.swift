import AppKit
import HeadroomCore

/// Offscreen renderer used to inspect the HUD in states the machine is not
/// currently in. `Headroom --render <dir>` writes one PNG per state.
@MainActor
enum Renderer {
    static func run(outputDir: String) {
        let dir = URL(fileURLWithPath: outputDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let geometry = NotchGeometry.current()
        let usage = UsageTracker()
        let rolled = PS.scan()
        let live = CandidateBuilder.build(rolled: rolled, usage: usage)

        // Real machine state.
        let real = PressureMonitor.evaluate(PressureMonitor.currentSample())
        write(state("live", geometry: geometry, reading: real, items: rank(live)), to: dir, name: "01-live-expanded")

        // A machine in trouble, which is the state that matters most.
        let critical = PressureReading(
            sample: MemorySample(totalBytes: 16 * 1_073_741_824, freeBytes: 180 * 1_048_576,
                                 purgeableBytes: 90 * 1_048_576, fileBackedBytes: 600 * 1_048_576,
                                 compressedBytes: 4 * 1_073_741_824, swapUsedBytes: 3_113_851_290),
            level: .critical, score: 0.93)
        write(state("critical", geometry: geometry, reading: critical, items: rank(live)),
              to: dir, name: "02-critical")

        // The notification, which is how the HUD speaks first.
        let note = NotchContentView(geometry: geometry, reading: critical)
        note.items = rank(live)
        note.mode = .notification
        note.frame = geometry.expandedFrame(contentHeight: NotchContentView.notificationHeight,
                                            width: HUDMode.notification.panelWidth)
        note.rebuild()
        note.layoutSubtreeIfNeeded()
        write(note, to: dir, name: "05-notification")

        // Nothing worth suggesting.
        write(state("empty", geometry: geometry, reading: real, items: []), to: dir, name: "03-empty")

        // Collapsed pill, in all three levels.
        for (name, reading) in [("comfortable", real), ("critical", critical)] {
            let v = NotchContentView(geometry: geometry, reading: reading)
            v.mode = .collapsed
            v.frame = NSRect(origin: .zero, size: geometry.collapsedSize)
            v.rebuild()
            write(v, to: dir, name: "04-collapsed-\(name)")
        }

        print("rendered to \(dir.path)")
        exit(0)
    }

    private static func rank(_ c: [Candidate]) -> [RankedCandidate] {
        Ranker.rank(c, now: Date(), config: RankConfig.default)
    }

    private static func state(_ label: String, geometry: NotchGeometry,
                              reading: PressureReading, items: [RankedCandidate]) -> NotchContentView {
        let v = NotchContentView(geometry: geometry, reading: reading)
        v.items = items
        v.mode = .expanded
        v.frame = geometry.expandedFrame(contentHeight: 0)
        v.rebuild()
        v.frame = geometry.expandedFrame(contentHeight: v.contentHeight, width: HUDMode.expanded.panelWidth)
        v.layoutSubtreeIfNeeded()
        return v
    }

    static let backdrop = NSColor(srgbRed: 0.28, green: 0.30, blue: 0.34, alpha: 1)

    private static func write(_ view: NSView, to dir: URL, name: String) {
        // Pad and back with a mid-tone so the shell's edges and shadow are
        // visible against something, the way they are over a desktop.
        let pad: CGFloat = 24
        let size = NSSize(width: view.bounds.width + pad * 2, height: view.bounds.height + pad * 2)
        let image = NSImage(size: size)
        image.lockFocus()
        backdrop.setFill()
        NSRect(origin: .zero, size: size).fill()

        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            // The cache rep has no alpha channel, so prime it with the same
            // backdrop rather than letting untouched pixels come out white.
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            backdrop.setFill()
            NSRect(origin: .zero, size: rep.size).fill(using: .copy)
            NSGraphicsContext.restoreGraphicsState()
            view.cacheDisplay(in: view.bounds, to: rep)
            rep.draw(in: NSRect(x: pad, y: pad, width: view.bounds.width, height: view.bounds.height))
        }
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
