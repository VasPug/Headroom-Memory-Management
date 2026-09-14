import AppKit
import Foundation

/// Joins the rolled-up process tree to the list of running apps, so each
/// entry carries an app's identity with its whole subtree's memory.
@MainActor
public enum CandidateBuilder {
    /// A background process must be at least this big before it is worth
    /// mentioning — higher than the app floor, because a stray process is a
    /// riskier suggestion than a visible app.
    public static let backgroundFloor: Int64 = 500 * 1024 * 1024

    /// Never suggest these, whatever they weigh. Quitting any of them either
    /// does nothing useful or breaks the session.
    static let neverSuggest: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver",
        "com.apple.controlcenter", "com.apple.notificationcenterui",
        "com.apple.WindowManager", "com.apple.loginwindow",
    ]

    static let systemPrefixes = [
        "/System/", "/usr/", "/sbin/", "/bin/", "/Library/Apple/",
        "/Library/Application Support/com.apple",
    ]

    /// What counts as "last used" when Headroom has not seen the app focused
    /// yet. An app's launch time is a real lower bound on how long it has sat
    /// untouched, and it beats showing nothing on the first day.
    nonisolated public static func effectiveLastUsed(observed: Date?, launched: Date?) -> Date? {
        observed ?? launched
    }

    public static func build(rolled: [RolledProcess], usage: UsageTracker) -> [Candidate] {
        let apps = NSWorkspace.shared.runningApplications
        let byPID = Dictionary(
            apps.compactMap { app -> (Int32, NSRunningApplication)? in (app.processIdentifier, app) },
            uniquingKeysWith: { a, _ in a }
        )
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let me = ProcessInfo.processInfo.processIdentifier
        let uid = getuid()

        return rolled.compactMap { proc -> Candidate? in
            if proc.root.pid == me { return nil }
            guard proc.root.uid == uid else { return nil }  // never touch another user's or the system's processes

            if let app = byPID[proc.root.pid], let bundleID = app.bundleIdentifier {
                guard !neverSuggest.contains(bundleID) else { return nil }
                guard app.activationPolicy != .prohibited else { return nil }
                return Candidate(
                    id: bundleID,
                    name: app.localizedName ?? bundleID,
                    kind: .app,
                    pid: proc.root.pid,
                    memoryBytes: proc.totalRSSBytes,
                    cpuPercent: proc.totalCPUPercent,
                    lastUsed: effectiveLastUsed(observed: usage.date(for: bundleID), launched: app.launchDate),
                    isFrontmost: app.processIdentifier == frontmostPID
                )
            }

            // No app identity: a standalone background process.
            guard proc.totalRSSBytes >= backgroundFloor else { return nil }
            guard !systemPrefixes.contains(where: { proc.root.command.hasPrefix($0) }) else { return nil }
            return Candidate(
                id: proc.root.command,
                name: (proc.root.command as NSString).lastPathComponent,
                kind: .process,
                pid: proc.root.pid,
                memoryBytes: proc.totalRSSBytes,
                cpuPercent: proc.totalCPUPercent,
                lastUsed: nil,
                isFrontmost: false
            )
        }
    }

    /// Graceful only. Apps get a normal quit so unsaved-work prompts still
    /// appear; processes get SIGTERM. Nothing here force-kills.
    @discardableResult
    public static func quit(_ candidate: Candidate) -> Bool {
        switch candidate.kind {
        case .app:
            guard let app = NSRunningApplication(processIdentifier: candidate.pid) else { return false }
            return app.terminate()
        case .process:
            return kill(candidate.pid, SIGTERM) == 0
        }
    }
}
