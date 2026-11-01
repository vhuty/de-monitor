import AppKit
import DisplaySwitcherCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var debounceTimer: Timer?
    private var lastApplied: PhysicalPort?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Emoji has no menu-bar glyph (renders as "?"); use an SF Symbol.
            let icon = NSImage(systemSymbolName: "display.2", accessibilityDescription: "de-monitor")
                ?? NSImage(systemSymbolName: "display", accessibilityDescription: "de-monitor")
            button.image = icon
            button.toolTip = "de-monitor: USB-C display switcher"
        }
        rebuildMenu(port: .unknown, signal: PortSignal())

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
        let (signal, port) = Detector.classified()
        rebuildMenu(port: port, signal: signal)
        guard port != .unknown else {
            NSLog("de-monitor: unknown port (PortID=%@ Address=%@), skipping auto-apply",
                  String(describing: signal.portID), signal.address ?? "nil")
            return
        }
        if port == lastApplied && reason == "reconfig" {
            return
        }
        guard let profile = ProfileStore.load().layouts.profile(for: port) else {
            NSLog("de-monitor: no saved layout for %@, skipping (arrange + Remember current)", port.rawValue)
            rebuildMenu(port: port, signal: signal)
            return
        }
        if LayoutApplier.matches(profile) {
            lastApplied = port
            NSLog("de-monitor: %@ layout already active, skipping reconfig", port.rawValue)
            rebuildMenu(port: port, signal: signal)
            return
        }
        if LayoutApplier.apply(profile) {
            lastApplied = port
            NSLog("de-monitor: applied %@ layout for %@ (%@)", port.rawValue,
                  signal.productName ?? "?", reason)
        } else {
            NSLog("de-monitor: apply failed (single display?)")
        }
        rebuildMenu(port: port, signal: signal)
    }

    // MARK: - Menu

    private func savedState(_ profile: DisplayProfile?) -> String {
        guard let profile else { return "—" }
        return "(\(profile.internalOrigin.x),\(profile.internalOrigin.y))"
    }

    private func rebuildMenu(port: PhysicalPort, signal: PortSignal) {
        let menu = NSMenu()
        let statusTitle = port == .unknown
            ? "Port: unknown (no/undetected external)"
            : "Port: \(port.rawValue) — \(port.displayName)"
        let status = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let detail = NSMenuItem(
            title: "PortID \(signal.portID.map(String.init) ?? "-") · \(signal.address ?? "-")",
            action: nil, keyEquivalent: "")
        detail.isEnabled = false
        menu.addItem(detail)

        let stored = ProfileStore.load()
        let layoutsState = NSMenuItem(
            title: "Saved: left \(savedState(stored.layouts.left)) · right \(savedState(stored.layouts.right))",
            action: nil, keyEquivalent: "")
        layoutsState.isEnabled = false
        menu.addItem(layoutsState)
        menu.addItem(.separator())

        let remember = NSMenuItem(title: "Remember current for this port…",
                                  action: #selector(rememberCurrent), keyEquivalent: "")
        remember.target = self
        remember.isEnabled = (port != .unknown)
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
        let (signal, port) = Detector.classified()
        guard port != .unknown else { return }
        guard let origin = LayoutApplier.currentOrigins().internalOrigin else { return }
        var stored = ProfileStore.load()
        let profile = DisplayProfile(internalOrigin: origin, note: "remembered via menu \(Date())")
        if port == .left { stored.layouts.left = profile } else { stored.layouts.right = profile }
        try? ProfileStore.save(stored)
        rebuildMenu(port: port, signal: signal)
    }

    @objc private func toggleAutostart() {
        do {
            try Autostart.setEnabled(!Autostart.isEnabled)
        } catch {
            NSLog("de-monitor: autostart toggle failed: \(error)")
        }
        let (signal, port) = Detector.classified()
        rebuildMenu(port: port, signal: signal)
    }
}

enum MonitorApp {
    @MainActor static weak var shared: AppDelegate?
}
