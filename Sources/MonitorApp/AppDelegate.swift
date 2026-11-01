import AppKit
import DisplaySwitcherCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var debounceTimer: Timer?
    private var lastAppliedKey: String?
    private var pendingFlags: CGDisplayChangeSummaryFlags = []
    private var cooldownUntil = Date.distantPast

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

        // Debounce covers link training after replug; flags from a burst
        // of events are OR-ed so an Add is never lost.
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            if flags.contains(.beginConfigurationFlag) { return }
            DispatchQueue.main.async {
                MonitorApp.shared?.scheduleSwitch(reason: "reconfig", flags: flags)
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

    func scheduleSwitch(reason: String, flags: CGDisplayChangeSummaryFlags = []) {
        pendingFlags.formUnion(flags)
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.detectAndApply(reason: reason)
        }
    }

    private func detectAndApply(reason: String) {
        let flags = pendingFlags
        pendingFlags = []
        let signal = Detector.detect()
        let key = signal.key
        rebuildMenu(signal: signal)
        guard signal.hasIdentity else {
            NSLog("de-monitor: no external display, skipping")
            return
        }
        // Add (or launch/wake): port context may have changed -> restore
        // saved setup, or snapshot current as the initial one.
        // Moved/shape-changed: user rearranged in Settings -> snapshot.
        if flags.contains(.addFlag) || reason == "launch" || reason == "wake" {
            restoreOrInit(signal: signal, key: key)
        } else {
            snapshotOnMove(signal: signal, key: key)
        }
    }

    private func restoreOrInit(signal: PortSignal, key: String) {
        guard let profile = ProfileStore.load()[key] else {
            NSLog("de-monitor: no saved setup for %@, snapshotting current", key)
            snapshotCurrent(signal: signal, key: key)
            return
        }
        if LayoutApplier.matches(profile) {
            lastAppliedKey = key
            NSLog("de-monitor: setup for %@ already active, skipping reconfig", key)
            return
        }
        if LayoutApplier.apply(profile) {
            lastAppliedKey = key
            cooldownUntil = Date().addingTimeInterval(5)
            NSLog("de-monitor: applied saved setup for %@", key)
        } else {
            NSLog("de-monitor: apply failed (single display?)")
        }
        rebuildMenu(signal: signal)
    }

    private func snapshotOnMove(signal: PortSignal, key: String) {
        // Moves right after our own apply are its echo, not the user.
        if Date() < cooldownUntil {
            NSLog("de-monitor: ignoring move during post-apply cooldown")
            return
        }
        snapshotCurrent(signal: signal, key: key)
    }

    private func snapshotCurrent(signal: PortSignal, key: String) {
        let origins = LayoutApplier.currentOrigins()
        guard let origin = origins.internalOrigin, origins.external != nil else {
            NSLog("de-monitor: snapshot skipped (need 2 active displays)")
            return
        }
        var setups = ProfileStore.load()
        let profile = DisplayProfile(internalOrigin: origin)
        if setups[key] == profile {
            NSLog("de-monitor: snapshot for %@ unchanged, skipping write", key)
            return
        }
        setups[key] = profile
        do {
            try ProfileStore.save(setups)
            NSLog("de-monitor: snapshot saved for %@: internal (%d,%d)", key, Int(origin.x), Int(origin.y))
        } catch {
            NSLog("de-monitor: snapshot save failed: %@", String(describing: error))
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

        let saved: DisplayProfile? = signal.hasIdentity ? ProfileStore.load()[signal.key] : nil
        let state = NSMenuItem(
            title: saved.map { "saved (\($0.internalOrigin.x),\($0.internalOrigin.y))" } ?? "—",
            action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())

        let autostart = NSMenuItem(title: "Start at login: \(Autostart.isEnabled ? "on" : "off")",
                                   action: #selector(toggleAutostart), keyEquivalent: "")
        autostart.target = self
        menu.addItem(autostart)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
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
