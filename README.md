# de-monitor? 🤔

macOS MenuBar app + CLI that restores the display arrangement
for the USB-C port the external monitor is plugged into.

## How it works

- Plug the monitor into a USB-C port → restores the arrangement last saved for that port.
- Rearrange displays in System Settings → arrangement is remembered automatically.
- No port change on launch/wake → current arrangement is left untouched.

## Requirements

- macOS 14+
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
