import AppKit
import DisplaySwitcherCore

let delegate = AppDelegate()
MonitorApp.shared = delegate
let app = NSApplication.shared
app.delegate = delegate
// LSUIElement agent: no dock icon, menu-bar only (see Info.plist when bundled).
app.setActivationPolicy(.accessory)
app.run()
