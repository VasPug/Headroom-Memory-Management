import Foundation
import HeadroomCore

private let MB: Int64 = 1024 * 1024

// Real `ps -axo pid,ppid,rss,pcpu,uid,comm` output. RSS is in KB and the
// command is the last field but contains spaces, which is the whole reason
// this needs a real parser rather than a split().
private let chromeFixture = """
  PID  PPID    RSS  %CPU   UID COMM
    1     0  11520   0.0     0 /sbin/launchd
91414     1 210848   6.9   501 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
91417     1   6272   0.0   501 /Applications/Google Chrome.app/Contents/Frameworks/chrome_crashpad_handler
91421 91414  76672   9.0   501 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome Helper
91422 91414  64240   0.0   501 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome Helper
"""

func runProcessScannerTests() {
    T.test("parse reads every non-header row") {
        let rows = PS.parse(chromeFixture)
        T.equal(rows.count, 5, "row count")
    }

    T.test("parse converts RSS from KB to bytes") {
        let rows = PS.parse(chromeFixture)
        let chrome = rows.first { $0.pid == 91414 }!
        T.equal(chrome.rssBytes, 210848 * 1024, "chrome RSS")
    }

    T.test("parse keeps spaces in the command path") {
        let rows = PS.parse(chromeFixture)
        let helper = rows.first { $0.pid == 91421 }!
        T.equal(helper.command, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome Helper", "command")
        T.equal(helper.ppid, 91414, "ppid")
        T.equal(helper.cpuPercent, 9.0, "cpu")
        T.equal(helper.uid, 501, "uid")
    }

    T.test("parse skips malformed lines instead of crashing") {
        let rows = PS.parse("garbage\n\n  PID  PPID\n42 1 100 0.0 501 /bin/thing\n")
        T.equal(rows.count, 1, "only the valid row survives")
    }

    T.test("rollUp sums a multi-process app into its root") {
        let rolled = PS.rollUp(PS.parse(chromeFixture))
        let chrome = rolled.first { $0.root.pid == 91414 }!
        // 210848 + 76672 + 64240 KB, crashpad excluded (its ppid is 1, so it is its own root)
        T.equal(chrome.totalRSSBytes, (210848 + 76672 + 64240) * 1024, "rolled RSS")
        T.equal(chrome.processCount, 3, "process count")
        T.equal(chrome.totalCPUPercent, 15.9, "rolled CPU")
    }

    T.test("rollUp treats a pid-1 child as its own root") {
        let rolled = PS.rollUp(PS.parse(chromeFixture))
        T.expect(rolled.contains { $0.root.pid == 91417 }, "crashpad handler is a separate root")
    }

    T.test("rollUp carries grandchildren up to the root") {
        let rows = PS.parse("""
        100 1 1000 0.0 501 /app/Main
        200 100 2000 0.0 501 /app/Child
        300 200 4000 0.0 501 /app/Grandchild
        """)
        let rolled = PS.rollUp(rows)
        T.equal(rolled.count, 1, "one root")
        T.equal(rolled[0].totalRSSBytes, 7000 * 1024, "grandchild included")
        T.equal(rolled[0].processCount, 3, "all three counted")
    }

    T.test("rollUp adopts a process whose parent is missing from the table") {
        let rows = PS.parse("777 555 8000 0.0 501 /app/Orphan")
        let rolled = PS.rollUp(rows)
        T.equal(rolled.count, 1, "orphan becomes its own root")
        T.equal(rolled[0].root.pid, 777, "root pid")
    }

    T.test("rollUp survives a parent cycle without hanging") {
        let rows = PS.parse("""
        10 11 1000 0.0 501 /a
        11 10 2000 0.0 501 /b
        """)
        let rolled = PS.rollUp(rows)
        T.expect(!rolled.isEmpty, "cycle still produces output")
    }
}
