import Foundation
import HeadroomCore

private let GB: Int64 = 1024 * 1024 * 1024

private func reading(thrashMBs: Double = 0, diskFreeGB: Double = 300,
                     kernel: KernelPressure = .normal) -> PressureReading {
    PressureMonitor.evaluate(MemorySample(
        totalBytes: 16 * GB, freeBytes: 4 * GB, purgeableBytes: 2 * GB, fileBackedBytes: 2 * GB,
        compressedBytes: 0, swapUsedBytes: 4 * GB,
        swapOutBytesPerSec: thrashMBs * 1_000_000, swapInBytesPerSec: thrashMBs * 1_000_000,
        diskFreeBytes: Int64(diskFreeGB * Double(GB)), kernelPressure: kernel))
}

private func calm() -> PressureReading { reading() }

func runNudgePolicyTests() {
    T.test("the machine starting to thrash alerts") {
        var p = NudgePolicy()
        T.expect(p.shouldNotify(reading(thrashMBs: 8)), "warn fires")
    }

    T.test("continuing to thrash at the same level does not keep alerting") {
        var p = NudgePolicy()
        _ = p.shouldNotify(reading(thrashMBs: 8))
        T.expect(!p.shouldNotify(reading(thrashMBs: 9)), "no repeat")
        T.expect(!p.shouldNotify(reading(thrashMBs: 10)), "still no repeat")
    }

    T.test("getting worse alerts again immediately, with no waiting period") {
        var p = NudgePolicy()
        T.expect(p.shouldNotify(reading(thrashMBs: 8)), "warn")
        T.expect(p.shouldNotify(reading(thrashMBs: 30)), "critical right after")
    }

    T.test("one calm reading is not a recovery") {
        var p = NudgePolicy()
        _ = p.shouldNotify(reading(thrashMBs: 8))
        _ = p.shouldNotify(calm())
        T.expect(!p.shouldNotify(reading(thrashMBs: 8)), "a single quiet sample proves nothing")
    }

    // This is the case the old swap-total model could never reach: rates fall
    // back to zero on their own, so recovery actually happens.
    T.test("a sustained calm period re-arms, and the next episode alerts") {
        var p = NudgePolicy()
        _ = p.shouldNotify(reading(thrashMBs: 8))
        for _ in 0..<NudgePolicy.calmSamplesToRearm { _ = p.shouldNotify(calm()) }
        T.expect(p.shouldNotify(reading(thrashMBs: 8)), "alerts again")
    }

    T.test("a full disk alerts") {
        var p = NudgePolicy()
        T.expect(p.shouldNotify(reading(diskFreeGB: 2)), "critical")
    }

    T.test("an escalation with nothing to suggest is not spent") {
        var p = NudgePolicy()
        T.expect(!p.shouldNotify(reading(thrashMBs: 8), hasRecommendation: false), "quiet")
        T.expect(p.shouldNotify(reading(thrashMBs: 8), hasRecommendation: true), "fires once it can help")
    }

    T.test("recovery still re-arms even with nothing to suggest") {
        var p = NudgePolicy()
        _ = p.shouldNotify(reading(thrashMBs: 8))
        for _ in 0..<NudgePolicy.calmSamplesToRearm { _ = p.shouldNotify(calm(), hasRecommendation: false) }
        T.expect(p.shouldNotify(reading(thrashMBs: 8)), "re-armed")
    }
}

func runNudgeRecommendationTests() {}
