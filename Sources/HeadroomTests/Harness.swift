import Foundation

/// Minimal assertion harness. Xcode's XCTest is unavailable under
/// Command Line Tools, so tests run as a plain executable that exits
/// non-zero when anything fails.
enum T {
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var current = ""

    static func test(_ name: String, _ body: () throws -> Void) {
        current = name
        do { try body() } catch { failures.append("\(name): threw \(error)") }
    }

    static func expect(_ cond: Bool, _ msg: String, file: StaticString = #file, line: UInt = #line) {
        checks += 1
        if !cond { failures.append("\(current): \(msg)  [\(file):\(line)]") }
    }

    static func equal<V: Equatable>(_ a: V, _ b: V, _ msg: String = "", file: StaticString = #file, line: UInt = #line) {
        checks += 1
        if a != b { failures.append("\(current): \(msg) expected \(b), got \(a)  [\(file):\(line)]") }
    }

    static func finish() -> Never {
        if failures.isEmpty {
            print("✅ \(checks) checks passed")
            exit(0)
        }
        print("❌ \(failures.count) failure(s) of \(checks) checks:")
        failures.forEach { print("   • \($0)") }
        exit(1)
    }
}
