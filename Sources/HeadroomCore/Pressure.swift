import Foundation

/// macOS's own verdict, from `kern.memorystatus_vm_pressure_level`.
public enum KernelPressure: Int, Sendable, Equatable {
    case normal = 1, warn = 2, critical = 4
}

/// Raw paging counters. They only mean something as a difference over time.
public struct VMCounters: Sendable, Equatable {
    public let swapins: UInt64
    public let swapouts: UInt64
    public let timestamp: TimeInterval

    public init(swapins: UInt64, swapouts: UInt64, timestamp: TimeInterval) {
        self.swapins = swapins
        self.swapouts = swapouts
        self.timestamp = timestamp
    }

    public static func rates(from a: VMCounters, to b: VMCounters,
                             pageSize: Int64) -> (inBytesPerSec: Double, outBytesPerSec: Double) {
        let seconds = b.timestamp - a.timestamp
        guard seconds > 0 else { return (0, 0) }
        // Counters reset across reboots; never report a negative rate.
        let ins = b.swapins >= a.swapins ? b.swapins - a.swapins : 0
        let outs = b.swapouts >= a.swapouts ? b.swapouts - a.swapouts : 0
        return (Double(ins) * Double(pageSize) / seconds,
                Double(outs) * Double(pageSize) / seconds)
    }
}

public struct MemorySample: Equatable, Sendable {
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let purgeableBytes: Int64
    public let fileBackedBytes: Int64
    public let compressedBytes: Int64
    /// Total swap in use. A high-water mark: it climbs and essentially never
    /// falls, so it says how much has ever been paged out, not how much trouble
    /// the machine is in now.
    public let swapUsedBytes: Int64
    public let swapOutBytesPerSec: Double
    public let swapInBytesPerSec: Double
    /// Swap can only grow into free space on the boot volume. When this runs
    /// out is when macOS puts up "your system has run out of application memory".
    public let diskFreeBytes: Int64
    public let kernelPressure: KernelPressure

    public init(totalBytes: Int64, freeBytes: Int64, purgeableBytes: Int64, fileBackedBytes: Int64,
                compressedBytes: Int64, swapUsedBytes: Int64, swapOutBytesPerSec: Double,
                swapInBytesPerSec: Double, diskFreeBytes: Int64, kernelPressure: KernelPressure) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.purgeableBytes = purgeableBytes
        self.fileBackedBytes = fileBackedBytes
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapOutBytesPerSec = swapOutBytesPerSec
        self.swapInBytesPerSec = swapInBytesPerSec
        self.diskFreeBytes = diskFreeBytes
        self.kernelPressure = kernelPressure
    }

    public var availableBytes: Int64 { freeBytes + purgeableBytes + fileBackedBytes }
    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    /// How full memory is. Informational only: a Mac at 90% with nothing moving
    /// is working exactly as designed.
    public var utilization: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }
    /// Pages leaving and returning at the same time. This is what makes a Mac
    /// lag, and what the old model missed entirely.
    public var thrashBytesPerSec: Double { min(swapOutBytesPerSec, swapInBytesPerSec) }
}

public enum PressureLevel: String, Sendable, Equatable {
    case comfortable, warn, critical
}

public struct PressureReading: Equatable, Sendable {
    public let sample: MemorySample
    public let level: PressureLevel
    /// Drives the meter's length. Severity drives its colour; these are
    /// deliberately different things.
    public let utilization: Double
    /// Plain words for what is wrong, or nil when nothing is.
    public let reason: String?

    public init(sample: MemorySample, level: PressureLevel, utilization: Double, reason: String?) {
        self.sample = sample
        self.level = level
        self.utilization = utilization
        self.reason = reason
    }
}

public enum PressureMonitor {
    static let MB = 1_000_000.0
    /// Sustained two-way swapping, in bytes/sec.
    static let warnThrash = 4 * MB
    static let criticalThrash = 15 * MB
    /// Swap growing this fast means memory is being exhausted right now.
    static let warnSwapOut = 15 * MB
    static let criticalSwapOut = 50 * MB
    static let criticalDiskBytes: Int64 = 3 * 1024 * 1024 * 1024
    static let warnDiskBytes: Int64 = 10 * 1024 * 1024 * 1024

    /// Judges the machine on what actually degrades it: pages thrashing in and
    /// out, swap unable to grow, and the kernel's own verdict. Notably absent is
    /// the amount of memory in use, which on macOS is meant to be high.
    public static func evaluate(_ s: MemorySample) -> PressureReading {
        var level = PressureLevel.comfortable
        var reason: String?

        func raise(_ new: PressureLevel, _ why: String) {
            let rank: (PressureLevel) -> Int = { $0 == .critical ? 2 : ($0 == .warn ? 1 : 0) }
            guard rank(new) >= rank(level) else { return }
            level = new
            reason = why
        }

        let thrash = s.thrashBytesPerSec
        if thrash >= criticalThrash {
            raise(.critical, "Swapping \(mbs(thrash)) both ways — this is the lag")
        } else if thrash >= warnThrash {
            raise(.warn, "Swapping \(mbs(thrash)) both ways")
        }

        if s.swapOutBytesPerSec >= criticalSwapOut {
            raise(.critical, "Swapping out \(mbs(s.swapOutBytesPerSec)) — memory is running out now")
        } else if s.swapOutBytesPerSec >= warnSwapOut {
            raise(.warn, "Swapping out \(mbs(s.swapOutBytesPerSec))")
        }

        if s.diskFreeBytes < criticalDiskBytes {
            raise(.critical, "Only \(gb(s.diskFreeBytes)) free on disk — swap cannot grow")
        } else if s.diskFreeBytes < warnDiskBytes, s.swapUsedBytes > 0 {
            raise(.warn, "Disk is low (\(gb(s.diskFreeBytes))) and swap is in use")
        }

        switch s.kernelPressure {
        case .critical: raise(.critical, "macOS reports critical memory pressure")
        case .warn: raise(.warn, "macOS reports memory pressure")
        case .normal: break
        }

        return PressureReading(sample: s, level: level, utilization: s.utilization, reason: reason)
    }

    private static func mbs(_ bytes: Double) -> String {
        String(format: "%.0f MB/s", bytes / MB)
    }
    private static func gb(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }
}
