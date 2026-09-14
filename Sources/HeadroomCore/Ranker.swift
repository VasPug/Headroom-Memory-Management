import Foundation

public enum CandidateKind: String, Sendable, Equatable {
    case app      // has a Dock icon; quit gracefully, unsaved-work prompts still appear
    case process  // background hog; SIGTERM
}

public struct Candidate: Sendable, Equatable {
    public let id: String       // bundle identifier, or executable path for a process
    public let name: String
    public let kind: CandidateKind
    public let pid: Int32
    public let memoryBytes: Int64
    public let cpuPercent: Double
    /// When this app was last frontmost. nil means Headroom has never seen it
    /// focused — true for background processes, and for apps launched before
    /// Headroom started.
    public let lastUsed: Date?
    public let isFrontmost: Bool

    public init(id: String, name: String, kind: CandidateKind, pid: Int32, memoryBytes: Int64,
                cpuPercent: Double, lastUsed: Date?, isFrontmost: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.pid = pid
        self.memoryBytes = memoryBytes
        self.cpuPercent = cpuPercent
        self.lastUsed = lastUsed
        self.isFrontmost = isFrontmost
    }
}

public struct RankConfig: Sendable {
    public var protectedIDs: Set<String>
    public var minMemoryBytes: Int64
    /// Anything touched more recently than this is off limits.
    public var minIdle: TimeInterval
    public var busyCPUPercent: Double
    public var busyPenalty: Double
    /// Idle time assumed for something with no usage history: enough to be a
    /// real candidate, not enough to beat a measurably stale app.
    public var unknownIdle: TimeInterval

    public static let `default` = RankConfig(
        protectedIDs: [],
        minMemoryBytes: 250 * 1024 * 1024,
        minIdle: 5 * 60,
        busyCPUPercent: 20,
        busyPenalty: 0.25,
        unknownIdle: 30 * 60
    )

    public init(protectedIDs: Set<String>, minMemoryBytes: Int64, minIdle: TimeInterval,
                busyCPUPercent: Double, busyPenalty: Double, unknownIdle: TimeInterval) {
        self.protectedIDs = protectedIDs
        self.minMemoryBytes = minMemoryBytes
        self.minIdle = minIdle
        self.busyCPUPercent = busyCPUPercent
        self.busyPenalty = busyPenalty
        self.unknownIdle = unknownIdle
    }
}

public struct RankedCandidate: Sendable, Equatable {
    public let candidate: Candidate
    public let score: Double
    public let idle: TimeInterval
}

public enum Ranker {
    /// Ranks what is worth quitting: big, cold, and not doing anything.
    public static func rank(_ candidates: [Candidate], now: Date, config: RankConfig) -> [RankedCandidate] {
        candidates.compactMap { c -> RankedCandidate? in
            if c.isFrontmost { return nil }
            if config.protectedIDs.contains(c.id) { return nil }
            if c.memoryBytes < config.minMemoryBytes { return nil }

            let measuredIdle = c.lastUsed.map { now.timeIntervalSince($0) }
            if let idle = measuredIdle, idle < config.minIdle { return nil }
            let idle = measuredIdle ?? config.unknownIdle

            let gb = Double(c.memoryBytes) / 1_073_741_824
            let hours = max(0, idle) / 3600
            // log keeps a day-old app from swamping a two-hour-old one that is
            // four times the size; memory stays the dominant term.
            var score = gb * log2(1 + hours)

            if c.cpuPercent >= config.busyCPUPercent { score *= config.busyPenalty }

            return RankedCandidate(candidate: c, score: score, idle: idle)
        }
        .sorted {
            $0.score == $1.score ? $0.candidate.memoryBytes > $1.candidate.memoryBytes : $0.score > $1.score
        }
    }
}
