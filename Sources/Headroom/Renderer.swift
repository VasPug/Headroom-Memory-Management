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
        var sampler = PressureSampler()
        _ = sampler.sample()
        Thread.sleep(forTimeInterval: 2)   // give the rates a baseline
        let real = PressureMonitor.evaluate(sampler.sample())
        write(state("live", geometry: geometry, reading: real, items: rank(live)), to: dir, name: "01-live-expanded")

        // A machine actually in trouble: pages going out and coming straight
        // back, which is what makes a Mac lag.
        let critical = PressureMonitor.evaluate(MemorySample(
            totalBytes: 16 * 1_073_741_824, freeBytes: 180 * 1_048_576,
            purgeableBytes: 90 * 1_048_576, fileBackedBytes: 600 * 1_048_576,
            compressedBytes: 4 * 1_073_741_824, swapUsedBytes: 8 * 1_073_741_824,
            swapOutBytesPerSec: 34_000_000, swapInBytesPerSec: 28_000_000,
            diskFreeBytes: 120 * 1_073_741_824, kernelPressure: .warn))
        write(state("critical", geometry: geometry, reading: critical, items: rank(live)),
              to: dir, name: "02-critical")

        // The notification, which is how the HUD speaks first.
        let note = NotchContentView(geometry: geometry, reading: real)
        note.items = rank(live)
        note.mode = .notification
        note.frame = geometry.expandedFrame(contentHeight: NotchContentView.notificationHeight,
                                            width: HUDMode.notification.panelWidth)
        note.rebuild()
        note.layoutSubtreeIfNeeded()
        write(note, to: dir, name: "05-notification")

        // The full ramp: same machine, three different situations.
        let ramp: [(String, Double, Double, Double, KernelPressure)] = [
            ("healthy", 13.8, 0, 1.3, .normal),        // high usage, nothing moving
            ("strain", 14.2, 8, 8, .normal),           // starting to thrash
            ("struggling", 15.2, 34, 28, .warn),       // thrashing hard
        ]
        for (name, usedGB, outMBs, inMBs, kern) in ramp {
            let total: Int64 = 16 * 1_073_741_824
            let avail = total - Int64(usedGB * 1_073_741_824)
            let s = MemorySample(totalBytes: total, freeBytes: avail / 3, purgeableBytes: avail / 3,
                                 fileBackedBytes: avail - 2 * (avail / 3), compressedBytes: 0,
                                 swapUsedBytes: 8 * 1_073_741_824,
                                 swapOutBytesPerSec: outMBs * 1_000_000,
                                 swapInBytesPerSec: inMBs * 1_000_000,
                                 diskFreeBytes: 300 * 1_073_741_824, kernelPressure: kern)
            write(state(name, geometry: geometry, reading: PressureMonitor.evaluate(s), items: rank(live)),
                  to: dir, name: "06-level-\(name)")
        }

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
