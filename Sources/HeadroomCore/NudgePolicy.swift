import Foundation

/// Decides when the HUD is allowed to speak up.
///
/// This is event driven, not rate limited: every time pressure gets worse than
/// anything already reported, it alerts, immediately. What it will not do is
/// repeat itself while the situation is unchanged, or fire twice because a
/// reading wobbled across a threshold. Re-arming needs a genuine recovery, not
/// the passage of time.
public struct NudgePolicy: Sendable {
    /// The worst level already reported in the current episode.
    public private(set) var reported: PressureLevel = .comfortable

    /// Pressure must fall clearly below the warning line before the policy will
    /// alert again, so a value hovering on the boundary cannot machine-gun.
    public static let rearmRatio = PressureMonitor.warnRatio - 0.08

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
        let recovered = reading.sample.usageRatio < Self.rearmRatio
            && reading.sample.swapUsedBytes < PressureMonitor.warnSwapBytes
        if recovered {
            reported = .comfortable
            return false
        }

        guard rank(reading.level) > rank(reported) else { return false }
        guard hasRecommendation else { return false }
        reported = reading.level
        return true
    }
}
