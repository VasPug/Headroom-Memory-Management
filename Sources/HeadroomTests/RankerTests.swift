import Foundation
import HeadroomCore

private let MB: Int64 = 1024 * 1024
private let GB: Int64 = 1024 * 1024 * 1024
private let now = Date(timeIntervalSince1970: 1_700_000_000)

private func candidate(
    _ id: String,
    memory: Int64,
    idleHours: Double,
    cpu: Double = 0,
    frontmost: Bool = false,
    kind: CandidateKind = .app,
    neverUsed: Bool = false
) -> Candidate {
    Candidate(
        id: id,
        name: id,
        kind: kind,
        pid: Int32(abs(id.hashValue % 30000)),
        memoryBytes: memory,
        cpuPercent: cpu,
        lastUsed: neverUsed ? nil : now.addingTimeInterval(-idleHours * 3600),
        isFrontmost: frontmost
    )
}

func runRankerTests() {
    let config = RankConfig.default

    T.test("the app you are looking at is never a candidate") {
        let ranked = Ranker.rank([
            candidate("Frontmost", memory: 8 * GB, idleHours: 0, frontmost: true),
            candidate("Idle", memory: 1 * GB, idleHours: 5),
        ], now: now, config: config)
        T.equal(ranked.count, 1, "only the idle app survives")
        T.equal(ranked[0].candidate.id, "Idle", "survivor")
    }

    T.test("protected ids are excluded") {
        var c = config
        c.protectedIDs = ["com.apple.finder"]
        let ranked = Ranker.rank([
            candidate("com.apple.finder", memory: 4 * GB, idleHours: 10),
            candidate("Other", memory: 1 * GB, idleHours: 10),
        ], now: now, config: c)
        T.equal(ranked.count, 1, "finder filtered out")
        T.equal(ranked[0].candidate.id, "Other", "survivor")
    }

    T.test("more memory and more idle time ranks higher") {
        let ranked = Ranker.rank([
            candidate("Small", memory: 400 * MB, idleHours: 6),
            candidate("Huge", memory: 6 * GB, idleHours: 6),
            candidate("Medium", memory: 2 * GB, idleHours: 6),
        ], now: now, config: config)
        T.equal(ranked.map(\.candidate.id), ["Huge", "Medium", "Small"], "order by memory at equal idle")
    }

    T.test("at equal memory, the app idle longer ranks higher") {
        let ranked = Ranker.rank([
            candidate("Recent", memory: 2 * GB, idleHours: 1),
            candidate("Stale", memory: 2 * GB, idleHours: 20),
        ], now: now, config: config)
        T.equal(ranked[0].candidate.id, "Stale", "stale first")
    }

    T.test("an app burning CPU is pushed down so active work is not killed") {
        let busy = candidate("Building", memory: 4 * GB, idleHours: 8, cpu: 90)
        let quiet = candidate("Sleeping", memory: 2 * GB, idleHours: 8, cpu: 0)
        let ranked = Ranker.rank([busy, quiet], now: now, config: config)
        T.equal(ranked[0].candidate.id, "Sleeping", "quiet app outranks the busy bigger one")
    }

    T.test("apps below the memory floor are not worth suggesting") {
        let ranked = Ranker.rank([
            candidate("Tiny", memory: 20 * MB, idleHours: 40),
            candidate("Real", memory: 1 * GB, idleHours: 2),
        ], now: now, config: config)
        T.equal(ranked.count, 1, "tiny filtered")
        T.equal(ranked[0].candidate.id, "Real", "survivor")
    }

    T.test("an app used moments ago is not suggested") {
        let ranked = Ranker.rank([
            candidate("JustUsed", memory: 5 * GB, idleHours: 0.01),
            candidate("Idle", memory: 1 * GB, idleHours: 4),
        ], now: now, config: config)
        T.equal(ranked.count, 1, "just-used filtered")
        T.equal(ranked[0].candidate.id, "Idle", "survivor")
    }

    T.test("an app never seen since launch is treated as neutral, not top") {
        let ranked = Ranker.rank([
            candidate("Unknown", memory: 2 * GB, idleHours: 0, neverUsed: true),
            candidate("KnownStale", memory: 2 * GB, idleHours: 24),
        ], now: now, config: config)
        T.equal(ranked[0].candidate.id, "KnownStale", "a measured stale app beats an unknown one")
        T.expect(ranked.contains { $0.candidate.id == "Unknown" }, "unknown still appears")
    }

    T.test("background processes have no usage history and rank on memory alone") {
        let ranked = Ranker.rank([
            candidate("node", memory: 3 * GB, idleHours: 0, kind: .process, neverUsed: true),
            candidate("SmallApp", memory: 500 * MB, idleHours: 3, kind: .app),
        ], now: now, config: config)
        T.equal(ranked[0].candidate.id, "node", "the 3GB runaway leads")
    }

    T.test("idle time is reported for display") {
        let ranked = Ranker.rank([candidate("A", memory: 1 * GB, idleHours: 3)], now: now, config: config)
        T.equal(ranked[0].idle, 3 * 3600, "idle seconds")
    }
}

func runColdStartTests() {
    let observed = Date(timeIntervalSince1970: 1_700_000_000)
    let launched = Date(timeIntervalSince1970: 1_699_000_000)

    T.test("observed usage wins over launch time") {
        T.equal(CandidateBuilder.effectiveLastUsed(observed: observed, launched: launched), observed, "observed")
    }
    T.test("launch time fills in before any usage has been observed") {
        T.equal(CandidateBuilder.effectiveLastUsed(observed: nil, launched: launched), launched, "launched")
    }
    T.test("with neither, it stays unknown rather than guessing") {
        T.expect(CandidateBuilder.effectiveLastUsed(observed: nil, launched: nil) == nil, "nil")
    }
}
