import Foundation

enum Fmt {
    static func gb(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    /// Compact size that switches to MB below a gigabyte.
    static func size(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb < 1 { return String(format: "%.0f MB", Double(bytes) / 1_048_576) }
        return String(format: "%.1f GB", gb)
    }

    static func idle(_ seconds: TimeInterval, known: Bool) -> String {
        guard known else { return "not used since launch" }
        let mins = Int(seconds / 60)
        if mins < 60 { return "idle \(max(1, mins))m" }
        let hours = mins / 60
        if hours < 24 { return "idle \(hours)h \(mins % 60)m" }
        return "idle \(hours / 24)d \(hours % 24)h"
    }
}
