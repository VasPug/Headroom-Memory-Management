import Foundation
import HeadroomCore

private let GB: Int64 = 1024 * 1024 * 1024

private func sample(
    usedGB: Double = 8,
    swapGB: Double = 0,
    swapOutMBs: Double = 0,
    swapInMBs: Double = 0,
    diskFreeGB: Double = 300,
    kernel: KernelPressure = .normal,
    totalGB: Double = 16
) -> MemorySample {
    let total = Int64(totalGB * Double(GB))
    let avail = total - Int64(usedGB * Double(GB))
    return MemorySample(
        totalBytes: total,
        freeBytes: avail / 3,
        purgeableBytes: avail / 3,
        fileBackedBytes: avail - 2 * (avail / 3),
        compressedBytes: 0,
        swapUsedBytes: Int64(swapGB * Double(GB)),
        swapOutBytesPerSec: swapOutMBs * 1_000_000,
        swapInBytesPerSec: swapInMBs * 1_000_000,
        diskFreeBytes: Int64(diskFreeGB * Double(GB)),
        kernelPressure: kernel)
}

func runPressureTests() {
    T.test("available memory is free plus purgeable plus file-backed") {
        let s = MemorySample(totalBytes: 16 * GB, freeBytes: 1 * GB, purgeableBytes: 2 * GB,
                             fileBackedBytes: 3 * GB, compressedBytes: 0, swapUsedBytes: 0,
                             swapOutBytesPerSec: 0, swapInBytesPerSec: 0,
                             diskFreeBytes: 300 * GB, kernelPressure: .normal)
        T.equal(s.availableBytes, 6 * GB, "available")
        T.equal(s.usedBytes, 10 * GB, "used")
        T.equal(Int(s.utilization * 100), 62, "utilization percent")
    }

    // The bug this model replaces: a machine sitting at high usage with swap
    // allocated but nothing actually moving is not in trouble, and macOS agrees.
    T.test("high usage with idle swap is healthy, not critical") {
        let s = sample(usedGB: 13.8, swapGB: 8, swapOutMBs: 0, swapInMBs: 1.3, kernel: .normal)
        T.equal(PressureMonitor.evaluate(s).level, .comfortable, "not an emergency")
    }

    T.test("utilization is still reported so the meter stays honest") {
        let r = PressureMonitor.evaluate(sample(usedGB: 13.8))
        T.expect(r.utilization > 0.85, "meter reads full even while healthy: \(r.utilization)")
    }

    T.test("swap allocated but never touched says nothing at all") {
        T.equal(PressureMonitor.evaluate(sample(swapGB: 12)).level, .comfortable, "totals are a high-water mark")
    }

    // What actually makes a Mac unusable: pages going out and coming straight back.
    T.test("sustained two-way swapping is thrashing") {
        T.equal(PressureMonitor.evaluate(sample(swapOutMBs: 8, swapInMBs: 8)).level, .warn, "warn")
        T.equal(PressureMonitor.evaluate(sample(swapOutMBs: 30, swapInMBs: 25)).level, .critical, "critical")
    }

    T.test("reading back from swap alone is not thrashing") {
        T.equal(PressureMonitor.evaluate(sample(swapOutMBs: 0, swapInMBs: 40)).level, .comfortable, "reads are cheap")
    }

    T.test("filling swap fast is trouble even before anything comes back") {
        T.equal(PressureMonitor.evaluate(sample(swapOutMBs: 20, swapInMBs: 0)).level, .warn, "rapid growth warns")
        T.equal(PressureMonitor.evaluate(sample(swapOutMBs: 60, swapInMBs: 0)).level, .critical, "runaway")
    }

    // The real cause of "your system has run out of application memory".
    T.test("a nearly full disk is critical, because swap cannot grow") {
        T.equal(PressureMonitor.evaluate(sample(diskFreeGB: 2)).level, .critical, "no room for swap")
    }

    T.test("a tight disk warns once swap is in use") {
        T.equal(PressureMonitor.evaluate(sample(swapGB: 4, diskFreeGB: 8)).level, .warn, "warn")
        T.equal(PressureMonitor.evaluate(sample(swapGB: 0, diskFreeGB: 8)).level, .comfortable, "no swap, no risk yet")
    }

    T.test("plenty of disk keeps a big swap file harmless") {
        T.equal(PressureMonitor.evaluate(sample(swapGB: 8, diskFreeGB: 328)).level, .comfortable, "room to grow")
    }

    // Never quieter than the kernel.
    T.test("the kernel's own verdict is a floor") {
        T.equal(PressureMonitor.evaluate(sample(kernel: .warn)).level, .warn, "warn floor")
        T.equal(PressureMonitor.evaluate(sample(kernel: .critical)).level, .critical, "critical floor")
    }

    T.test("but we may still be louder than the kernel when thrashing") {
        let s = sample(swapOutMBs: 30, swapInMBs: 30, kernel: .normal)
        T.equal(PressureMonitor.evaluate(s).level, .critical, "early warning is the point")
    }

    T.test("a zero-total sample does not divide by zero") {
        let s = MemorySample(totalBytes: 0, freeBytes: 0, purgeableBytes: 0, fileBackedBytes: 0,
                             compressedBytes: 0, swapUsedBytes: 0, swapOutBytesPerSec: 0,
                             swapInBytesPerSec: 0, diskFreeBytes: 0, kernelPressure: .normal)
        T.expect(PressureMonitor.evaluate(s).utilization.isFinite, "finite")
    }

    T.test("the reason names what is actually wrong") {
        T.expect(PressureMonitor.evaluate(sample(swapOutMBs: 30, swapInMBs: 25)).reason!.contains("Swapping"),
                 "thrash reason")
        T.expect(PressureMonitor.evaluate(sample(diskFreeGB: 2)).reason!.contains("disk"), "disk reason")
        T.expect(PressureMonitor.evaluate(sample()).reason == nil, "healthy says nothing")
    }
}

func runRateTests() {
    T.test("rates come from the delta between two counter readings") {
        let a = VMCounters(swapins: 1000, swapouts: 2000, timestamp: 100)
        let b = VMCounters(swapins: 1600, swapouts: 2000, timestamp: 110)
        let r = VMCounters.rates(from: a, to: b, pageSize: 16384)
        T.equal(Int(r.inBytesPerSec), 60 * 16384, "600 pages over 10s")
        T.equal(Int(r.outBytesPerSec), 0, "no swapouts")
    }

    T.test("a counter reset does not produce a negative rate") {
        let a = VMCounters(swapins: 5000, swapouts: 5000, timestamp: 100)
        let b = VMCounters(swapins: 10, swapouts: 10, timestamp: 110)
        let r = VMCounters.rates(from: a, to: b, pageSize: 16384)
        T.expect(r.inBytesPerSec >= 0 && r.outBytesPerSec >= 0, "clamped to zero")
    }

    T.test("two readings at the same instant do not divide by zero") {
        let a = VMCounters(swapins: 10, swapouts: 10, timestamp: 100)
        let r = VMCounters.rates(from: a, to: a, pageSize: 16384)
        T.expect(r.inBytesPerSec.isFinite && r.outBytesPerSec.isFinite, "finite")
    }
}
