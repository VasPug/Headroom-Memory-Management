import Foundation
import HeadroomCore

private let GB: Int64 = 1024 * 1024 * 1024

private func sample(usedGB: Double, swapGB: Double = 0, totalGB: Double = 16) -> MemorySample {
    let total = Int64(totalGB * Double(GB))
    let used = Int64(usedGB * Double(GB))
    // Everything not used is reclaimable; split it across the three buckets
    // that actually count as available on macOS.
    let avail = total - used
    return MemorySample(
        totalBytes: total,
        freeBytes: avail / 3,
        purgeableBytes: avail / 3,
        fileBackedBytes: avail - 2 * (avail / 3),
        compressedBytes: 0,
        swapUsedBytes: Int64(swapGB * Double(GB))
    )
}

func runPressureTests() {
    T.test("available memory is free plus purgeable plus file-backed") {
        let s = MemorySample(totalBytes: 16 * GB, freeBytes: 1 * GB, purgeableBytes: 2 * GB,
                             fileBackedBytes: 3 * GB, compressedBytes: 0, swapUsedBytes: 0)
        T.equal(s.availableBytes, 6 * GB, "available")
        T.equal(s.usedBytes, 10 * GB, "used")
    }

    T.test("a mostly empty machine is comfortable") {
        T.equal(PressureMonitor.evaluate(sample(usedGB: 5)).level, .comfortable, "level")
    }

    T.test("three quarters full warns, well before macOS would say anything") {
        T.equal(PressureMonitor.evaluate(sample(usedGB: 12)).level, .warn, "level")
    }

    T.test("nearly full is critical") {
        T.equal(PressureMonitor.evaluate(sample(usedGB: 15)).level, .critical, "level")
    }

    T.test("meaningful swap forces a warning even when usage looks fine") {
        // This is the case macOS hides from you until it is too late.
        let s = sample(usedGB: 8, swapGB: 2)
        let r = PressureMonitor.evaluate(s)
        T.expect(r.level != .comfortable, "swap escalates past comfortable, got \(r.level)")
    }

    T.test("heavy swap is critical regardless of usage ratio") {
        T.equal(PressureMonitor.evaluate(sample(usedGB: 8, swapGB: 6)).level, .critical, "level")
    }

    T.test("score stays inside 0...1") {
        let low = PressureMonitor.evaluate(sample(usedGB: 0))
        let high = PressureMonitor.evaluate(sample(usedGB: 16, swapGB: 32))
        T.expect(low.score >= 0 && low.score <= 1, "low in range: \(low.score)")
        T.expect(high.score >= 0 && high.score <= 1, "high in range: \(high.score)")
        T.expect(high.score > low.score, "more load scores higher")
    }

    T.test("a zero-total sample does not divide by zero") {
        let s = MemorySample(totalBytes: 0, freeBytes: 0, purgeableBytes: 0,
                             fileBackedBytes: 0, compressedBytes: 0, swapUsedBytes: 0)
        let r = PressureMonitor.evaluate(s)
        T.expect(r.score.isFinite, "score is finite")
    }
}
