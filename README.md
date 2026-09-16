# Headroom

A background agent that tells you what to quit **before** macOS tells you you're out of memory.

macOS only warns you at the cliff edge — by which point the machine is swapping so hard
you can't work the force-quit dialog. Headroom watches the gradient instead, learns which
apps you actually use, and asks you to close one while the Mac is still responsive.

## What it does

- **Lives on the notch.** A slim pill beside the notch shows a meter that fills as memory
  is consumed, green through amber to red. Hover it
  for the full list; it drops out of the notch like part of the hardware.
- **Judges the machine on what actually hurts.** Not "you're using a lot of memory" —
  macOS is *designed* to use nearly all of it. It watches the rate of pages swapping out
  and back in (thrashing, which is what makes a Mac lag), free space on the boot volume
  (swap can only grow into it, and running out is what triggers "your system has run out
  of application memory"), and the kernel's own `kern.memorystatus_vm_pressure_level`,
  which it will never undercut. Swap *totals* are deliberately ignored: they only ever
  climb, so they say nothing about right now.
- **Speaks up the moment things get worse.** Every escalation alerts immediately — into
  warning, and again if it goes on to critical. It slides out of the notch with one
  recommendation ("Quit Cursor? Frees 2.4 GB · idle 3d 1h"). Click it for the full list,
  hit Quit, or ignore it and it withdraws after nine seconds. It won't repeat itself while
  nothing has changed, and it re-arms only after memory genuinely recovers — not on a
  timer — so a reading wobbling across a threshold can't machine-gun you.
- **Learns your habits.** It watches which app is frontmost and remembers when you last
  touched each one. Ranking is memory × idle time, so the 2 GB thing you haven't looked at
  since Tuesday outranks the 3 GB thing you were in a minute ago.
- **Counts whole apps.** Memory is rolled up across the process tree, so Chrome shows its
  real footprint including every renderer, not the parent's 300 MB.
- **Never kills anything itself.** Apps get a graceful quit — unsaved-work prompts still
  appear. Background processes get SIGTERM. Nothing is force-killed, nothing is automatic.

## What it won't suggest

The app you're looking at, anything you touched in the last five minutes, anything burning
CPU (so it won't kill a running build), Finder/Dock/WindowServer, any process not owned by
you, and anything you've marked **Keep**.

## Install

Requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).
Full Xcode is not needed.

```sh
git clone <repo-url> Headroom
cd Headroom
./build-app.sh --install
```

That builds the app, puts it in `/Applications`, starts it, and registers a
LaunchAgent so it comes back at login. On first run it opens the panel once so
you can see where the pill lives.

To build without installing, run `./build-app.sh` and open `build/Headroom.app`.

## Uninstall

```sh
./build-app.sh --uninstall
```

Removes the app, the LaunchAgent, the preferences, and everything it learned
about you. To quit just this session without uninstalling, right-click the pill
and choose **Quit Headroom**.

## Tracking, and turning it off

Headroom records one thing: a timestamp of when each app was last frontmost. It
lives in `~/Library/Application Support/Headroom/usage.json`, it never leaves
your machine, and there is no network code in this project.

- **Erase learned usage** in the right-click menu wipes the file and starts over.
- **Quit Headroom** stops all recording; nothing is recorded while it is not running.
- `./build-app.sh --uninstall` removes the data along with the app.

No Accessibility or Screen Recording permission is requested, so Headroom cannot
see your keystrokes or your screen — only which app is in front, and what `ps`
reports.

## Using it

- **Click** the pill → full list. It stays open until you close it; hovering does nothing.
- **Close** button, `Esc`, or a click anywhere else → dismiss
- **Keep** (appears on row hover) → never suggest that app again
- **⌘-drag** the HUD → move the pill anywhere along the top of the screen
- **Right-click** → rescan, flip sides, erase learned usage, quit
- `kill -USR1 $(pgrep -x Headroom)` → replay the recommendation on demand

## Build

```sh
swift run HeadroomTests     # 46 checks
./build-app.sh              # builds build/Headroom.app
./build-app.sh --install    # installs to /Applications + starts at login
```

Uninstall: `launchctl bootout gui/$(id -u)/io.github.vaspug.headroom && rm -rf /Applications/Headroom.app ~/Library/LaunchAgents/io.github.vaspug.headroom.plist`

## Layout

| | |
|---|---|
| `HeadroomCore/ProcessScanner` | parses `ps`, folds subtrees into their root |
| `HeadroomCore/Pressure` | judges thrash rate, disk headroom and the kernel's verdict |
| `HeadroomCore/PressureSampler` | live VM counters; stateful, because rates need a baseline |
| `HeadroomCore/Ranker` | what's worth quitting: big, cold, and idle |
| `HeadroomCore/NudgePolicy` | when it is allowed to interrupt you |
| `HeadroomCore/UsageTracker` | per-app last-used times, persisted |
| `HeadroomCore/CandidateBuilder` | joins processes to apps; performs the quit |
| `Headroom/NotchContentView` | the HUD, cut from one path so it hangs off the notch |
| `Headroom/HUDController` | the pill → notification → panel state machine |
| `Headroom/NotchGeometry` | where the notch is, and where the HUD sits on it |

MIT licensed. Contributions welcome.
