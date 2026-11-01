import AppKit
import DisplaySwitcherCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var debounceTimer: Timer?
    private var lastApplied: PhysicalPort?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // SF Symbol renders natively in light/dark mode; emoji (e.g. 🖵)
            // has no glyph in the menu-bar font and shows as "?".
            let icon = NSImage(systemSymbolName: "display.2", accessibilityDescription: "de-monitor")
                ?? NSImage(systemSymbolName: "display", accessibilityDescription: "de-monitor")
            button.image = icon
            button.toolTip = "de-monitor: USB-C display switcher"
        }
        rebuildMenu(port: .unknown, signal: PortSignal())

        // Reconfiguration callback -> debounced detect+apply (link training needs ~2s).
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            // Ignore the begin-configuration notification; act on completion.
            if flags.contains(.beginConfigurationFlag) { return }
            DispatchQueue.main.async {
                MonitorApp.shared?.scheduleSwitch(reason: "reconfig")
            }
        }, nil)

        // Wake-from-sleep trigger (untested per plan — harmless if redundant).
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(onWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        // Initial: refresh menu, apply if external present.
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
        // Avoid redundant applies (e.g. duplicate callbacks for both displays).
        if port == lastApplied && reason == "reconfig" {
            // Still applied once per launch/wake; skip repeats.
            return
        }
        let profile = ProfileStore.load().layouts.profile(for: port)
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
