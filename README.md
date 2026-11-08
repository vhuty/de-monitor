# de-monitor? 🤔

macOS MenuBar app + CLI that restores the display arrangement
for the port the external monitor is plugged into (USB-C / HDMI).

## How it works

- Plug the monitor into a USB-C or HDMI port → restores the arrangement last saved for that port.
- Rearrange displays in System Settings → arrangement is remembered automatically.

## Requirements

- Apple Silicon MacBook with an external display (Intel Macs not supported: detection reads Apple Silicon display state; desktops without a built-in display can't save a two-display arrangement)
- macOS 14+ (tested on macOS 27.2, M4 Pro)
- Xcode toolchain

## Build

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swift build
xcrun swift test
```

## MenuBar app

```sh
xcrun swift run de-monitor-app
```

Runs in the menu bar, restores the saved setup on connect.
Menu: Arrange Displays shortcut, Reset configuration (when saved),
Start at login toggle, Quit.

## CLI

```sh
xcrun swift run de-monitor --detect
xcrun swift run de-monitor --status
xcrun swift run de-monitor --apply [port-key] [--force]
xcrun swift run de-monitor --remember
xcrun swift run de-monitor --list
```
