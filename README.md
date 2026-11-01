# de-monitor

macOS MenuBar app + CLI that restores the display arrangement for the
USB-C port the external monitor is plugged into.

Workflow: plug in → arrange displays in System Settings → save with
`de-monitor --remember` (or "Remember current" in the menu) → the app
restores that arrangement every time the same port is used. Ports
without a saved setup are left untouched.

## Detection signal (proven by A-B-A replug test)

Each socket reports stable IOKit facts: `PortID`
(`IOMobileFramebufferShim.DisplayAttributes`) and `Address`
(`AppleDisplayConnectionManager.ConnectionMapping`). Observed on this
hardware:

| PortID | Address |
|---|---|
| 0 | 0.0.0 |
| 16 | 0.1.0 |
| 32 | 0.2.0 |

The pair is used as-is (e.g. `32/0.2.0`) to key saved setups — no
interpretation of which physical socket it "should" be. No identifiable
port, or no saved setup for it → nothing is auto-applied.

Implementation note: the plan originally suggested `CGDisplayIOServicePort`
→ parent shim, but that API is marked unavailable in the macOS SDK, so
detection enumerates `IOMobileFramebufferShim` services directly (the
external monitor's shim is the one whose `DisplayAttributes` contains
`PortID`) and joins `ConnectionMapping` on `ProductName`. Read-only IOKit,
no entitlements.

Applying uses `CGBeginDisplayConfiguration → CGConfigureDisplayOrigin ×2 →
CGCompleteDisplayConfiguration` (same mechanism as displayplacer).
External stays at `(0,0)`, which keeps it the main display.

## Build

Requires Xcode toolchain (a standalone swiftly toolchain fails with
`unknown argument: '-target-arch-variant'`):

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swift build
xcrun swift test
```

Needs `/opt/homebrew/bin/displayplacer` only for manual inspection
(`displayplacer list`); not a runtime dependency.

## CLI

```sh
xcrun swift run de-monitor --detect    # PortID/Address/product/port key
xcrun swift run de-monitor --status    # detect + current layout + saved setups
xcrun swift run de-monitor --apply [port-key] [--force]  # default: current port; skips if already active or unsaved
xcrun swift run de-monitor --remember  # save current arrangement for the current port
xcrun swift run de-monitor --list      # current display origins
```

`~/.config/de-monitor/profiles.json` maps port key to arrangement —
nothing else:

```json
{"32/0.2.0": {"internalOrigin": {"x": -1512, "y": 278}}}
```

## MenuBar app

```sh
xcrun swift run de-monitor-app
```

`CGDisplayRegisterReconfigurationCallback` → ~2s debounce (link training)
→ detect → restore saved setup, plus a wake-from-sleep trigger. Menu shows
factual port info (`PortID · Address · product`), this-port saved state,
"remember current", login-item toggle (`SMAppService`), quit. Manual
restore stays available via `de-monitor --apply`. For `Start at login`
to work the binary must be bundled as a `.app` (packaging TBD).

## Files

- `Sources/DisplaySwitcherCore/` — `PortSignal` (opaque identity),
  `Detector` (IOKit), `Layouts` (profiles), `ProfileStore` (JSON),
  `LayoutApplier` (CoreGraphics)
- `Sources/DEMonitorCLI/` — CLI
- `Sources/MonitorApp/` — MenuBar agent
- `Tests/DisplaySwitcherCoreTests/` — classification tests

## Risks (per plan)

- Undocumented IOKit fields may change in future macOS → setups keyed by
  old values stop matching (re-run `--remember`); unknown ports are skipped.
- Sleep/wake path untested → debounce + wake trigger (verify on hardware).
