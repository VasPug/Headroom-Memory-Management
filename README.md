# Headroom

A background agent that tells you what to quit **before** macOS tells you you're out of memory.

macOS only warns you at the cliff edge — by which point the machine is swapping so hard
you can't work the force-quit dialog. Headroom watches the gradient instead, learns which
apps you actually use, and asks you to close one while the Mac is still responsive.

## What it does

- **Lives on the notch.** A slim pill beside the notch shows headroom remaining. Hover it
  for the full list; it drops out of the notch like part of the hardware.
- **Speaks first, once.** When pressure crosses into warning territory it slides out a
  notification with a single recommendation — "Quit Cursor? Frees 2.4 GB · idle 3d 1h".
  Click it for the full list, hit Quit, or ignore it and it withdraws after nine seconds.
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

## Using it

- **Hover** the pill → full list
- **Click** → panel stays open until you close it
- **Close** button, `Esc`, or a click anywhere else → dismiss
- **Keep** (appears on row hover) → never suggest that app again
- **Right-click** → rescan, flip to the other side of the notch, clear kept apps, quit
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
| `HeadroomCore/Pressure` | VM stats → a gradient that fires earlier than macOS does |
| `HeadroomCore/Ranker` | what's worth quitting: big, cold, and idle |
| `HeadroomCore/UsageTracker` | per-app last-used times, persisted |
| `HeadroomCore/CandidateBuilder` | joins processes to apps; performs the quit |
| `Headroom/NotchContentView` | the HUD, cut from one path so it hangs off the notch |
| `Headroom/HUDController` | the pill → notification → panel state machine |

Usage data lives in `~/Library/Application Support/Headroom/usage.json` and never leaves
the machine. No Accessibility or Screen Recording permissions are needed.
