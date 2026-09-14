import Foundation

public struct MemorySample: Equatable, Sendable {
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let purgeableBytes: Int64
    public let fileBackedBytes: Int64
    public let compressedBytes: Int64
    public let swapUsedBytes: Int64

    public init(totalBytes: Int64, freeBytes: Int64, purgeableBytes: Int64,
                fileBackedBytes: Int64, compressedBytes: Int64, swapUsedBytes: Int64) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.purgeableBytes = purgeableBytes
        self.fileBackedBytes = fileBackedBytes
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
    }

    /// What macOS can hand out without evicting anything that matters.
    public var availableBytes: Int64 { freeBytes + purgeableBytes + fileBackedBytes }
    public var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    public var usageRatio: Double {
        totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0
    }
}

public enum PressureLevel: String, Sendable, Equatable {
    case comfortable, warn, critical
}

public struct PressureReading: Equatable, Sendable {
    public let sample: MemorySample
    public let level: PressureLevel
    /// A continuous 0...1 gradient for the HUD. `level` drives decisions;
    /// this only drives how the bar looks.
    public let score: Double

    public init(sample: MemorySample, level: PressureLevel, score: Double) {
        self.sample = sample
        self.level = level
        self.score = score
    }
}

public enum PressureMonitor {
    public static let warnRatio = 0.70
    public static let criticalRatio = 0.85
    public static let warnSwapBytes: Int64 = 1 * 1024 * 1024 * 1024
    public static let criticalSwapBytes: Int64 = 4 * 1024 * 1024 * 1024
    static let swapScoreCeiling = 8.0  // GB of swap that counts as "fully bad"

    /// Deliberately fires earlier than macOS does. The system only escalates
    /// once it is already swapping hard, which is the point at which the
    /// machine is too slow to act on the warning.
    public static func evaluate(_ s: MemorySample) -> PressureReading {
        guard s.totalBytes > 0 else {
            return PressureReading(sample: s, level: .comfortable, score: 0)
        }

        let swapGB = Double(s.swapUsedBytes) / 1_073_741_824
        let swapFactor = min(1.0, swapGB / swapScoreCeiling)
        let score = min(1.0, max(0.0, 0.75 * s.usageRatio + 0.25 * swapFactor))

        var level: PressureLevel = .comfortable
        if s.usageRatio >= warnRatio { level = .warn }
        if s.usageRatio >= criticalRatio { level = .critical }
        // Swap is the honest signal that the machine is already hurting,
        // even when the usage ratio still looks survivable.
        if s.swapUsedBytes >= warnSwapBytes, level == .comfortable { level = .warn }
        if s.swapUsedBytes >= criticalSwapBytes { level = .critical }

        return PressureReading(sample: s, level: level, score: score)
    }

    /// Reads live VM statistics from the kernel.
    public static func currentSample() -> MemorySample {
        var rawPageSize: Int32 = 0
        var pageSizeLen = MemoryLayout<Int32>.size
        sysctlbyname("hw.pagesize", &rawPageSize, &pageSizeLen, nil, 0)
        let pageSize = Int64(rawPageSize > 0 ? rawPageSize : 16384)

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        var total: Int64 = 0
        var size = MemoryLayout<Int64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)

        guard result == KERN_SUCCESS else {
            return MemorySample(totalBytes: total, freeBytes: total, purgeableBytes: 0,
                                fileBackedBytes: 0, compressedBytes: 0, swapUsedBytes: 0)
        }

        // free_count includes speculative pages, which are really cache.
        let free = Int64(stats.free_count) - Int64(stats.speculative_count)
        return MemorySample(
            totalBytes: total,
            freeBytes: max(0, free) * pageSize,
            purgeableBytes: Int64(stats.purgeable_count) * pageSize,
            fileBackedBytes: Int64(stats.external_page_count) * pageSize,
            compressedBytes: Int64(stats.compressor_page_count) * pageSize,
            swapUsedBytes: Int64(swap.xsu_used)
        )
    }
}
