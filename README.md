# de-monitor? 🤔

macOS app that restores the display arrangement for the port the external monitor is plugged into.

## How it works

- Plug the monitor into a USB-C or HDMI port - restores the arrangement last saved for that port.
- Rearrange displays in System Settings - arrangement is remembered automatically.

## Requirements

- Apple Silicon MacBook with an external display (Intel Macs not supported)
- macOS 14+ (tested on macOS 27.2, M4 Pro)
- Xcode toolchain

## CLI

```sh
xcrun swift run de-monitor --detect
xcrun swift run de-monitor --status
xcrun swift run de-monitor --apply [port-key] [--force]
xcrun swift run de-monitor --remember
xcrun swift run de-monitor --list
```
