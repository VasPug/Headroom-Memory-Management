import Foundation

/// Decides when the HUD is allowed to speak up.
///
/// Event driven, not rate limited: any time pressure gets worse than what has
/// already been reported, it alerts immediately. It stays quiet while nothing
/// changes, and re-arms once the machine is genuinely calm again — measured by
/// the pressure level itself, which is now built from rates that fall back to
/// zero, rather than from swap totals that never come down.
public struct NudgePolicy: Sendable {
    public private(set) var reported: PressureLevel = .comfortable
    private var calmStreak = 0

    /// Consecutive calm readings before it will alert again. Rates fluctuate, so
    /// one quiet sample is not a recovery.
    public static let calmSamplesToRearm = 3

    public init() {}

    private func rank(_ level: PressureLevel) -> Int {
        switch level {
        case .comfortable: return 0
        case .warn: return 1
        case .critical: return 2
        }
    }

    /// - Parameter hasRecommendation: whether there is anything worth
    ///   suggesting. With nothing to say, the escalation is left unreported so
    ///   it still fires once a candidate appears.
    public mutating func shouldNotify(_ reading: PressureReading,
                                      hasRecommendation: Bool = true) -> Bool {
        if reading.level == .comfortable {
            calmStreak += 1
            if calmStreak >= Self.calmSamplesToRearm { reported = .comfortable }
            return false
        }
        calmStreak = 0

        guard rank(reading.level) > rank(reported) else { return false }
        guard hasRecommendation else { return false }
        reported = reading.level
        return true
    }
}
