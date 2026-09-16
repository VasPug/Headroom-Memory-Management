import Foundation
import HeadroomCore

/// `swift run HeadroomTests --state` — what the machine looks like right now.
func printLiveState() {
    func gb(_ b: Int64) -> String { String(format: "%.1f GB", Double(b) / 1_073_741_824) }
    func mbs(_ b: Double) -> String { String(format: "%.1f MB/s", b / 1_000_000) }

    var sampler = PressureSampler()
    _ = sampler.sample()                    // establish a baseline for the rates
    Thread.sleep(forTimeInterval: 5)
    let s = sampler.sample()
    let r = PressureMonitor.evaluate(s)

    print("memory used:   \(gb(s.usedBytes)) of \(gb(s.totalBytes))   (\(Int(s.utilization * 100))%)")
    print("swap total:    \(gb(s.swapUsedBytes))   <- high-water mark, not a live signal")
    print("swapping out:  \(mbs(s.swapOutBytesPerSec))")
    print("swapping in:   \(mbs(s.swapInBytesPerSec))")
    print("thrash:        \(mbs(s.thrashBytesPerSec))   <- what actually causes lag")
    print("disk free:     \(gb(s.diskFreeBytes))   <- swap can only grow into this")
    print("macOS says:    \(s.kernelPressure)")
    print("")
    print("VERDICT:       \(r.level.rawValue.uppercased())")
    print("reason:        \(r.reason ?? "nothing wrong")")
}
