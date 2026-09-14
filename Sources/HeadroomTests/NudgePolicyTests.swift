import Foundation
import HeadroomCore

private let GB: Int64 = 1024 * 1024 * 1024

private func reading(usedGB: Double, swapGB: Double = 0) -> PressureReading {
    let total = 16 * GB
    let avail = total - Int64(usedGB * Double(GB))
    return PressureMonitor.evaluate(MemorySample(
        totalBytes: total, freeBytes: avail / 3, purgeableBytes: avail / 3,
        fileBackedBytes: avail - 2 * (avail / 3), compressedBytes: 0,
        swapUsedBytes: Int64(swapGB * Double(GB))))
}

func runNudgePolicyTests() {
    T.test("crossing into warn alerts") {
        var p = NudgePolicy()
        T.expect(p.shouldNotify(reading(usedGB: 12)), "warn fires")
    }

    T.test("staying at warn does not keep alerting") {
        var p = NudgePolicy()
        _ = p.shouldNotify(reading(usedGB: 12))
        T.expect(!p.shouldNotify(reading(usedGB: 12.2)), "no repeat")
        T.expect(!p.shouldNotify(reading(usedGB: 12.5)), "still no repeat")
    }

    T.test("getting worse alerts again immediately, with no waiting period") {
        var p = NudgePolicy()
        T.expect(p.shouldNotify(reading(usedGB: 12)), "warn fires")
        // Escalation is new information. It must not be suppressed.
        T.expect(p.shouldNotify(reading(usedGB: 15)), "critical fires right after warn")
    }

    T.test("recovering part way does not re-arm") {
        var p = NudgePolicy()
        _ = p.shouldNotify(reading(usedGB: 15))
        _ = p.shouldNotify(reading(usedGB: 12))          // back to warn
        T.expect(!p.shouldNotify(reading(usedGB: 15)), "no alert without a real recovery")
    }

    T.test("hovering just under the threshold does not re-arm") {
        var p = NudgePolicy()
        _ = p.shouldNotify(reading(usedGB: 12))
        _ = p.shouldNotify(reading(usedGB: 11.1))        // comfortable, but barely
        T.expect(!p.shouldNotify(reading(usedGB: 12)), "flapping at the boundary stays quiet")
    }

    T.test("a real recovery re-arms, and the next climb alerts") {
        var p = NudgePolicy()
        _ = p.shouldNotify(reading(usedGB: 12))
        _ = p.shouldNotify(reading(usedGB: 6))           // you quit something
        T.expect(p.shouldNotify(reading(usedGB: 12)), "alerts again after recovering")
    }

    T.test("starting up already critical alerts straight away") {
        var p = NudgePolicy()
        T.expect(p.shouldNotify(reading(usedGB: 15.2)), "fires on first sample")
    }

    T.test("swap alone escalates") {
        var p = NudgePolicy()
        T.expect(p.shouldNotify(reading(usedGB: 8, swapGB: 2)), "swap fires")
        T.expect(p.shouldNotify(reading(usedGB: 8, swapGB: 6)), "heavier swap escalates again")
    }
}

func runNudgeRecommendationTests() {
    T.test("an escalation with nothing to suggest is not spent") {
        var p = NudgePolicy()
        T.expect(!p.shouldNotify(reading(usedGB: 12), hasRecommendation: false), "stays quiet")
        // The pressure has not changed, but now there is something to say.
        T.expect(p.shouldNotify(reading(usedGB: 12), hasRecommendation: true), "fires once it can help")
    }

    T.test("recovery still re-arms even with nothing to suggest") {
        var p = NudgePolicy()
        _ = p.shouldNotify(reading(usedGB: 12))
        _ = p.shouldNotify(reading(usedGB: 6), hasRecommendation: false)
        T.expect(p.shouldNotify(reading(usedGB: 12)), "re-armed")
    }
}
