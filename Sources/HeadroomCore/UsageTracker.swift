import AppKit
import Foundation

/// Remembers when each app was last frontmost. This is the part that only
/// works because Headroom runs continuously — after a day it knows your
/// habits, which is something no one-shot memory tool can tell you.
@MainActor
public final class UsageTracker {
    public private(set) var lastUsed: [String: Date] = [:]
    private let storeURL: URL
    private var dirty = false

    public init(storeURL: URL? = nil) {
        self.storeURL = storeURL ?? UsageTracker.defaultStoreURL()
        load()
    }

    public static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Headroom", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("usage.json")
    }

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.touch(id) }
        }
        // Whatever is frontmost right now counts as used right now.
        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier { touch(id) }

        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    public func touch(_ bundleID: String) {
        lastUsed[bundleID] = Date()
        dirty = true
    }

    public func date(for bundleID: String?) -> Date? {
        guard let bundleID else { return nil }
        return lastUsed[bundleID]
    }

    /// Called when an app disappears, so a relaunch later starts clean.
    public func forget(_ bundleID: String) {
        lastUsed.removeValue(forKey: bundleID)
        dirty = true
    }

    /// Forgets everything it has learned about you and removes the file.
    public func erase() {
        lastUsed = [:]
        dirty = false
        try? FileManager.default.removeItem(at: storeURL)
    }

    public func flush() {
        guard dirty else { return }
        let payload = lastUsed.mapValues { $0.timeIntervalSince1970 }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: storeURL, options: .atomic)
        dirty = false
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let payload = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return }
        lastUsed = payload.mapValues { Date(timeIntervalSince1970: $0) }
    }
}
