# de-monitor

macOS MenuBar app + CLI that auto-switches display arrangement based on which
USB-C port the external monitor is plugged into (MacBook Pro M4).

- **Left USB-C** → laptop under monitor (default centered: internal `(524,1440)`)
- **Right USB-C** → laptop left of monitor (measured: internal `(-1512,278)`)

## Detection signal (proven by A-B-A replug test)

| Port | `PortID` (`IOMobileFramebufferShim.DisplayAttributes`) | `Address` (`AppleDisplayConnectionManager.ConnectionMapping`) |
|---|---|---|
| Left #1 | 0 | 0.0.0 |
| Left #2 | 16 | 0.1.0 |
| Right | 32 | 0.2.0 |

Pattern: `Address = 0.{N}.0`, `PortID = 16×N`. Unknown values → graceful
fallback (no auto-apply) + manual mode via menu / `--apply`.

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
xcrun swift run de-monitor --detect    # (PortID, Address) -> port
xcrun swift run de-monitor --status    # detect + current layout + profiles
xcrun swift run de-monitor --apply [left|right]   # default: auto by port
xcrun swift run de-monitor --remember [left|right] # save current arrangement
xcrun swift run de-monitor --list      # current display origins
```

Profiles live in `~/.config/de-monitor/profiles.json` (created with
measured defaults on first `--remember`/menu use; missing file → defaults).

## MenuBar app

```sh
xcrun swift run de-monitor-app
```

`CGDisplayRegisterReconfigurationCallback` → ~2s debounce (link training)
→ detect → apply, plus a wake-from-sleep trigger. Menu shows detected
port + signal, per-port apply items, "remember current", login-item
toggle (`SMAppService`), quit. For `Start at login` to work the binary
must be bundled as a `.app` (packaging TBD).

## Files

- `Sources/DisplaySwitcherCore/` — `PortIdentity` (classify),
  `Detector` (IOKit), `Layouts` (profiles), `ProfileStore` (JSON),
  `LayoutApplier` (CoreGraphics)
- `Sources/DEMonitorCLI/` — CLI
- `Sources/MonitorApp/` — MenuBar agent
- `Tests/DisplaySwitcherCoreTests/` — classification tests

## Risks (per plan)

- Undocumented IOKit fields may change in future macOS → fallback + manual mode.
- Sleep/wake path untested → debounce + wake trigger (verify on hardware).
- Left ports measured once each → re-run `--detect` on each left port to confirm.
- "Below" default `(524,1440)` is computed centered, not measured — adjust
  with `--remember left` after arranging in System Settings.
