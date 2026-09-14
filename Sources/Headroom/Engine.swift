import AppKit
import HeadroomCore

/// Ties the three signals together: how much pressure the machine is under,
/// what is running, and what you have actually touched.
@MainActor
final class Engine {
    private(set) var reading = PressureMonitor.evaluate(PressureMonitor.currentSample())
    private(set) var ranked: [RankedCandidate] = []

    let usage = UsageTracker()
    var onUpdate: (() -> Void)?
    /// Fires when pressure first turns bad, so the HUD can announce itself.
    var onNudge: (() -> Void)?

    private var lastLevel: PressureLevel = .comfortable
    private var lastNudge = Date.distantPast
    private var scanning = false

    private let nudgeCooldown: TimeInterval = 30 * 60
    private let pressureInterval: TimeInterval = 3
    private let scanInterval: TimeInterval = 15

    var config: RankConfig {
        var c = RankConfig.default
        c.protectedIDs = Settings.protectedIDs
        return c
    }

    func start() {
        usage.start()
        samplePressure()
        rescan()

        Timer.scheduledTimer(withTimeInterval: pressureInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.samplePressure() }
        }
        Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescan() }
        }
    }

    private func samplePressure() {
        reading = PressureMonitor.evaluate(PressureMonitor.currentSample())
        onUpdate?()

        // Only nudge on the way up, and not more than twice an hour.
        let worsened = reading.level != lastLevel && reading.level != .comfortable
        let escalated = lastLevel == .comfortable || (lastLevel == .warn && reading.level == .critical)
        if worsened, escalated, Date().timeIntervalSince(lastNudge) > nudgeCooldown, !ranked.isEmpty {
            lastNudge = Date()
            onNudge?()
        }
        lastLevel = reading.level
    }

    func rescan() {
        guard !scanning else { return }
        scanning = true
        let usage = self.usage
        let config = self.config
        Task.detached(priority: .utility) {
            let rolled = PS.scan()
            await MainActor.run {
                let candidates = CandidateBuilder.build(rolled: rolled, usage: usage)
                self.ranked = Ranker.rank(candidates, now: Date(), config: config)
                self.scanning = false
                self.onUpdate?()
            }
        }
    }

    func quit(_ ranked: RankedCandidate) {
        CandidateBuilder.quit(ranked.candidate)
        // Drop it from the list immediately; the next scan confirms.
        self.ranked.removeAll { $0.candidate.pid == ranked.candidate.pid }
        onUpdate?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated { self?.rescan() }
        }
    }

    func protect(_ ranked: RankedCandidate) {
        Settings.protectedIDs.insert(ranked.candidate.id)
        self.ranked.removeAll { $0.candidate.id == ranked.candidate.id }
        onUpdate?()
    }
}

enum Settings {
    private static let key = "protectedIDs"

    static var protectedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: key) }
    }

    static var side: String {
        get { UserDefaults.standard.string(forKey: "side") ?? "right" }
        set { UserDefaults.standard.set(newValue, forKey: "side") }
    }
}
