import Foundation

/// Reads live memory statistics. Stateful, because the signals that matter are
/// rates: it needs the previous counters to know how fast pages are moving.
public struct PressureSampler: Sendable {
    private var previous: VMCounters?
    private let pageSize: Int64

    public init() {
        var raw: Int32 = 0
        var len = MemoryLayout<Int32>.size
        sysctlbyname("hw.pagesize", &raw, &len, nil, 0)
        pageSize = Int64(raw > 0 ? raw : 16384)
    }

    public mutating func sample() -> MemorySample {
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

        var kernelRaw: Int32 = 1
        var kernelSize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &kernelRaw, &kernelSize, nil, 0)
        let kernel = KernelPressure(rawValue: Int(kernelRaw)) ?? .normal

        guard result == KERN_SUCCESS else {
            return MemorySample(totalBytes: total, freeBytes: total, purgeableBytes: 0, fileBackedBytes: 0,
                                compressedBytes: 0, swapUsedBytes: 0, swapOutBytesPerSec: 0,
                                swapInBytesPerSec: 0, diskFreeBytes: Self.diskFree(), kernelPressure: kernel)
        }

        let now = VMCounters(swapins: stats.swapins, swapouts: stats.swapouts,
                             timestamp: Date().timeIntervalSince1970)
        // The first sample has no baseline, so rates start at zero.
        let rates: (inBytesPerSec: Double, outBytesPerSec: Double) =
            previous.map { VMCounters.rates(from: $0, to: now, pageSize: pageSize) } ?? (0, 0)
        previous = now

        let free = Int64(stats.free_count) - Int64(stats.speculative_count)
        return MemorySample(
            totalBytes: total,
            freeBytes: max(0, free) * pageSize,
            purgeableBytes: Int64(stats.purgeable_count) * pageSize,
            fileBackedBytes: Int64(stats.external_page_count) * pageSize,
            compressedBytes: Int64(stats.compressor_page_count) * pageSize,
            swapUsedBytes: Int64(swap.xsu_used),
            swapOutBytesPerSec: rates.outBytesPerSec,
            swapInBytesPerSec: rates.inBytesPerSec,
            diskFreeBytes: Self.diskFree(),
            kernelPressure: kernel)
    }

    static func diskFree() -> Int64 {
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let available = values.volumeAvailableCapacityForImportantUsage {
            return Int64(available)
        }
        return Int64.max   // unknown: do not invent a disk emergency
    }
}
