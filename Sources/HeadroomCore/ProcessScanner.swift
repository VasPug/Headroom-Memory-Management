import Foundation

/// One row of `ps` output.
public struct ProcRow: Equatable, Sendable {
    public let pid: Int32
    public let ppid: Int32
    public let rssBytes: Int64
    public let cpuPercent: Double
    public let uid: UInt32
    public let command: String

    public init(pid: Int32, ppid: Int32, rssBytes: Int64, cpuPercent: Double, uid: UInt32, command: String) {
        self.pid = pid
        self.ppid = ppid
        self.rssBytes = rssBytes
        self.cpuPercent = cpuPercent
        self.uid = uid
        self.command = command
    }
}

/// A root process with its whole subtree folded in. This is what makes
/// Chrome report its real footprint instead of the parent's slice.
public struct RolledProcess: Equatable, Sendable {
    public let root: ProcRow
    public let totalRSSBytes: Int64
    public let totalCPUPercent: Double
    public let processCount: Int
}

public enum PS {
    /// Parses `ps -axo pid,ppid,rss,pcpu,uid,comm`. The command is the last
    /// column but contains spaces, so it takes everything after five fields.
    public static func parse(_ output: String) -> [ProcRow] {
        var rows: [ProcRow] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard fields.count == 6,
                  let pid = Int32(fields[0]),
                  let ppid = Int32(fields[1]),
                  let rssKB = Int64(fields[2]),
                  let cpu = Double(fields[3]),
                  let uid = UInt32(fields[4])
            else { continue }  // header row and anything malformed
            rows.append(ProcRow(
                pid: pid,
                ppid: ppid,
                rssBytes: rssKB * 1024,
                cpuPercent: cpu,
                uid: uid,
                command: String(fields[5]).trimmingCharacters(in: .whitespaces)
            ))
        }
        return rows
    }

    /// Folds every process into its topmost ancestor. A process is a root when
    /// its parent is launchd (pid 1), the kernel (pid 0), or absent from the table.
    public static func rollUp(_ rows: [ProcRow]) -> [RolledProcess] {
        let byPID = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })

        func rootOf(_ row: ProcRow) -> ProcRow {
            var current = row
            var seen: Set<Int32> = [row.pid]
            while current.ppid != 0, current.ppid != 1, let parent = byPID[current.ppid] {
                if seen.contains(parent.pid) { break }  // cycle: stop where we are
                seen.insert(parent.pid)
                current = parent
            }
            return current
        }

        var totals: [Int32: (root: ProcRow, rss: Int64, cpu: Double, count: Int)] = [:]
        for row in rows {
            let root = rootOf(row)
            var entry = totals[root.pid] ?? (root, 0, 0, 0)
            entry.rss += row.rssBytes
            entry.cpu += row.cpuPercent
            entry.count += 1
            totals[root.pid] = entry
        }

        return totals.values.map {
            RolledProcess(
                root: $0.root,
                totalRSSBytes: $0.rss,
                // %CPU sums to noisy decimals; round to what ps itself reports.
                totalCPUPercent: ($0.cpu * 10).rounded() / 10,
                processCount: $0.count
            )
        }
        .sorted { $0.totalRSSBytes > $1.totalRSSBytes }
    }

    /// Runs `ps` and returns the rolled-up tree for the current user's processes.
    public static func scan() -> [RolledProcess] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid,ppid,rss,pcpu,uid,comm"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return rollUp(parse(String(decoding: data, as: UTF8.self)))
        } catch {
            return []
        }
    }
}
