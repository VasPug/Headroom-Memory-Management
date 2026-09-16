import AppKit
import HeadroomCore

/// Ties the three signals together: how much pressure the machine is under,
/// what is running, and what you have actually touched.
@MainActor
final class Engine {
    private var sampler = PressureSampler()
    private(set) var reading: PressureReading
    private(set) var ranked: [RankedCandidate] = []

    let usage = UsageTracker()

    init() {
        var bootstrap = PressureSampler()
        reading = PressureMonitor.evaluate(bootstrap.sample())
        sampler = bootstrap
    }
    var onUpdate: (() -> Void)?
    /// Fires when pressure first turns bad, so the HUD can announce itself.
    var onNudge: (() -> Void)?

    private var nudgePolicy = NudgePolicy()
    private var scanning = false

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
        reading = PressureMonitor.evaluate(sampler.sample())
        onUpdate?()

        // Every escalation is reported the moment it happens; the policy only
        // suppresses repeats and threshold wobble.
        if nudgePolicy.shouldNotify(reading, hasRecommendation: !ranked.isEmpty) {
            onNudge?()
        }
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

    /// Where the user dragged the pill to, if they ever did.
    static var pillX: CGFloat? {
        get { (UserDefaults.standard.object(forKey: "pillX") as? Double).map { CGFloat($0) } }
        set { UserDefaults.standard.set(newValue.map { Double($0) }, forKey: "pillX") }
    }

    static var hasLaunchedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: "hasLaunched") }
        set { UserDefaults.standard.set(newValue, forKey: "hasLaunched") }
    }
}
