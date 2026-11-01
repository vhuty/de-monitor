import AppKit
import DisplaySwitcherCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var debounceTimer: Timer?
    private var lastAppliedKey: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Emoji has no menu-bar glyph (renders as "?"); use an SF Symbol.
            let icon = NSImage(systemSymbolName: "display.2", accessibilityDescription: "de-monitor")
                ?? NSImage(systemSymbolName: "display", accessibilityDescription: "de-monitor")
            button.image = icon
            button.toolTip = "de-monitor: USB-C display switcher"
        }
        rebuildMenu(signal: PortSignal())

        // Debounce covers link training after replug.
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            if flags.contains(.beginConfigurationFlag) { return }
            DispatchQueue.main.async {
                MonitorApp.shared?.scheduleSwitch(reason: "reconfig")
            }
        }, nil)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(onWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        scheduleSwitch(reason: "launch")
    }

    @objc private func onWake() {
        scheduleSwitch(reason: "wake")
    }

    func scheduleSwitch(reason: String) {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.detectAndApply(reason: reason)
        }
    }

    private func detectAndApply(reason: String) {
        let signal = Detector.detect()
        let key = signal.key
        let setups = ProfileStore.load()
        let saved = key.isEmpty ? nil : setups[key]
        rebuildMenu(signal: signal)
        guard signal.hasIdentity else {
            NSLog("de-monitor: no external display, skipping auto-apply")
            return
        }
        if key == lastAppliedKey && reason == "reconfig" {
            return
        }
        guard let profile = saved else {
            NSLog("de-monitor: no saved setup for port %@, skipping (arrange + Remember current)", key)
            return
        }
        if LayoutApplier.matches(profile) {
            lastAppliedKey = key
            NSLog("de-monitor: setup for %@ already active, skipping reconfig", key)
            return
        }
        if LayoutApplier.apply(profile) {
            lastAppliedKey = key
            NSLog("de-monitor: applied saved setup for %@ (%@)", key, reason)
        } else {
            NSLog("de-monitor: apply failed (single display?)")
        }
        rebuildMenu(signal: signal)
    }

    // MARK: - Menu

    private func rebuildMenu(signal: PortSignal) {
        let menu = NSMenu()

        let title: String
        if signal.hasIdentity {
            let name = signal.productName ?? "External display"
            let portID = signal.portID.map(String.init) ?? "-"
            let address = signal.address ?? "-"
            title = "\(name) (PortID \(portID) · \(address))"
        } else {
            title = "No external display"
        }
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let remember = NSMenuItem(title: "Remember current for this port…",
                                  action: #selector(rememberCurrent), keyEquivalent: "")
        remember.target = self
        remember.isEnabled = signal.hasIdentity
        menu.addItem(remember)

        let autostart = NSMenuItem(title: "Start at login: \(Autostart.isEnabled ? "on" : "off")",
                                   action: #selector(toggleAutostart), keyEquivalent: "")
        autostart.target = self
        menu.addItem(autostart)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func rememberCurrent() {
        let signal = Detector.detect()
        guard signal.hasIdentity else { return }
        guard let origin = LayoutApplier.currentOrigins().internalOrigin else { return }
        var setups = ProfileStore.load()
        setups[signal.key] = DisplayProfile(internalOrigin: origin)
        try? ProfileStore.save(setups)
        lastAppliedKey = signal.key
        rebuildMenu(signal: signal)
    }

    @objc private func toggleAutostart() {
        do {
            try Autostart.setEnabled(!Autostart.isEnabled)
        } catch {
            NSLog("de-monitor: autostart toggle failed: \(error)")
        }
        let signal = Detector.detect()
        rebuildMenu(signal: signal)
    }
}

enum MonitorApp {
    @MainActor static weak var shared: AppDelegate?
}
