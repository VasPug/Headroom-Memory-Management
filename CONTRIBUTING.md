# Contributing to Headroom

Thanks for taking a look. This is a small, focused project and contributions are welcome.

## Getting set up

```sh
git clone https://github.com/VasPug/Headroom-Memory-Management.git
cd Headroom-Memory-Management
swift build
swift run HeadroomTests
```

You need **macOS 14+** and the Xcode Command Line Tools (`xcode-select --install`). Full
Xcode is not required and the project does not use an `.xcodeproj`.

## Running the tests

```sh
swift run HeadroomTests
```

Tests are a **plain executable**, not XCTest. This is deliberate: neither XCTest nor
swift-testing ships with the Command Line Tools, and requiring a 15 GB Xcode install to run
a test suite is a bad trade for a utility this size. The harness is about 30 lines in
`Sources/HeadroomTests/Harness.swift`. It exits non-zero on failure, so CI works normally.

Add tests by writing a `func runYourTests()` and calling it from `main.swift`:

```swift
T.test("what the behaviour should be, in a sentence") {
    T.equal(actual, expected, "what this assertion checks")
    T.expect(condition, "why this must hold")
}
```

## What has tests, and what doesn't

Everything in `HeadroomCore` is pure logic and **must** have tests — the `ps` tree rollup,
the pressure model, the ranker, the nudge policy. These are where the real bugs have been.

The AppKit HUD in `Sources/Headroom/` is verified by rendering it offscreen:

```sh
swift build && .build/debug/Headroom --render /tmp/shots
```

This writes a PNG per state, including ones your machine isn't currently in (a thrashing
Mac, an empty list). Please include before/after renders in PRs that change the UI.

To see what your Mac looks like to Headroom right now:

```sh
swift run HeadroomTests --state
```

## Design principles

Three rules the project tries hard to keep:

1. **Never quit anything without the user clicking.** Apps get a graceful
   `terminate()` so unsaved-work prompts still appear; background processes get `SIGTERM`.
   No force-kills, no automatic quitting, ever.
2. **Never cry wolf.** Headroom must never report worse than the kernel does without a
   concrete, defensible reason (measured thrashing, or a disk that can no longer host
   swap). High memory usage on its own is not a problem and must not be reported as one.
3. **Measure, don't assume.** Every threshold in `Pressure.swift` should be justifiable
   against a real measurement. If you change one, say in the PR what you observed.

## Pull requests

- One concern per PR.
- Run `swift run HeadroomTests` before pushing; CI runs the same command.
- Explain *why* in the commit message, not just what. If you fixed a wrong behaviour,
  describe the behaviour that was wrong.
- No new dependencies without discussion. The project deliberately has zero.

## Reporting bugs

Please include the output of:

```sh
swift run HeadroomTests --state
sw_vers
```

For HUD placement or drawing issues, a screenshot and your display arrangement
(built-in only, or which external monitors) help a lot — several past bugs only
appeared with an external display attached.

## Code of conduct

Be decent to each other. Harassment or personal attacks aren't welcome here, and
maintainers may remove comments or contributors that don't meet that bar.
