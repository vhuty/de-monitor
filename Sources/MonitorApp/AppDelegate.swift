import AppKit
import DisplaySwitcherCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {    private var statusItem: NSStatusItem!
    private var debounceTimer: Timer?
    private var pendingFlags: CGDisplayChangeSummaryFlags = []
    private var cooldownUntil = Date.distantPast
    private var launchedAt = Date()
    private var settleTimer: Timer?
    private var initialSnapshotTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchedAt = Date()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Custom glyph: monitor right-back + laptop left-front,
            // composited from SF Symbols at runtime (no assets) and rendered as a template for the tint.
            let icon = makeStatusIcon()
                ?? NSImage(systemSymbolName: "display.2", accessibilityDescription: "de-monitor")
            icon?.isTemplate = true
            button.image = icon
            button.toolTip = "de-monitor: USB-C display switcher"
        }
        rebuildMenu(signal: PortSignal())

        // Debounce covers link training after replug; flags from a burst
        // of events are OR-ed so an Add is never lost.
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            if flags.contains(.beginConfigurationFlag) { return }
            DispatchQueue.main.async {
                MonitorApp.shared?.scheduleSwitch(flags: flags)
            }
        }, nil)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(onWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        scheduleSwitch()
        scheduleInitialSnapshot()
    }

    @objc private func onWake() {
        scheduleSwitch()
    }

    func scheduleSwitch(flags: CGDisplayChangeSummaryFlags = []) {
        pendingFlags.formUnion(flags)
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            // Timer blocks are nonisolated; hop onto the actor. The timer
            // fires on the main runloop, so this costs nothing in practice.
            Task { @MainActor in self?.detectAndApply() }
        }
    }

    private func detectAndApply() {
        let flags = pendingFlags
        pendingFlags = []
        let signal = Detector.detect()
        let key = signal.key
        rebuildMenu(signal: signal)
        guard signal.hasIdentity else {
            NSLog("de-monitor: no external display, skipping")
            return
        }
        let moved = flags.contains(.movedFlag) || flags.contains(.desktopShapeChangedFlag)
        if flags.contains(.addFlag) {
            restoreOrInit(signal: signal, key: key, flags: flags)
        } else if moved {
            snapshotWhenSettled(signal: signal, key: key)
        } else if let profile = ProfileStore.load()[key] {
            if LayoutApplier.matches(profile) {
                NSLog("de-monitor: setup for %@ already active", key)
            } else {
                // No port change (launch/wake/mode change): a mismatch here may be
                // a deliberate user state, so never yank it back. Restoring happens
                // on Add only; a user arrange will snapshot via a Moved event.
                NSLog("de-monitor: arrangement differs from saved for %@, leaving untouched (no port change)", key)
            }
        } else {
            NSLog("de-monitor: no saved setup for %@ yet (arrange in Settings to create one)", key)
        }
    }

    private func restoreOrInit(signal: PortSignal, key: String, flags: CGDisplayChangeSummaryFlags) {
        guard let profile = ProfileStore.load()[key] else {
            // Adopt the user's arrangement only if one is already happening
            // in this window; never persist a system default as a setup.
            if flags.contains(.movedFlag) || flags.contains(.desktopShapeChangedFlag) {
                snapshotWhenSettled(signal: signal, key: key)
            } else {
                NSLog("de-monitor: no saved setup for %@, doing nothing (arrange in Settings to create one)", key)
            }
            return
        }
        if LayoutApplier.matches(profile) {
            NSLog("de-monitor: setup for %@ already active, skipping reconfig", key)
            return
        }
        if LayoutApplier.apply(profile) {
            cooldownUntil = Date().addingTimeInterval(5)
            NSLog("de-monitor: applied saved setup for %@", key)
        } else {
            NSLog("de-monitor: apply failed (single display?)")
        }
        rebuildMenu(signal: signal)
    }

    private func scheduleInitialSnapshot() {
        // First launch with a monitor but no saved setup: adopt the current
        // arrangement once, past the launch-settling window. Still goes
        // through the settle check, so boot transients are not persisted.
        // Wake is out of scope: only a fresh process has no event history.
        let delay = max(0, 16 - Date().timeIntervalSince(launchedAt))
        initialSnapshotTimer?.invalidate()
        initialSnapshotTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let signal = Detector.detect()
                guard signal.hasIdentity else { return }
                guard ProfileStore.load()[signal.key] == nil else { return }
                NSLog("de-monitor: no saved setup for %@, adopting current arrangement", signal.key)
                self.snapshotWhenSettled(signal: signal, key: signal.key)
            }
        }
    }

    private func snapshotWhenSettled(signal: PortSignal, key: String, attempts: Int = 3) {
        // Moves right after our own apply are its echo, not the user.
        if Date() < cooldownUntil {
            NSLog("de-monitor: ignoring move during post-apply cooldown")
            return
        }
        // The system may still be settling right after launch.
        if Date().timeIntervalSince(launchedAt) < 15 {
            NSLog("de-monitor: ignoring move during launch settling")
            return
        }
        // Persist only a resting state: re-read after a pause, save only if
        // unchanged (mid-drag transients never match twice).
        settleTimer?.invalidate()
        let first = LayoutApplier.currentOrigins().internalOrigin
        settleTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if Date() < self.cooldownUntil {
                    // Our own apply landed mid-settle: retry after the cooldown
                    // instead of dropping a possible user adjustment.
                    if attempts > 1 {
                        let delay = self.cooldownUntil.timeIntervalSinceNow + 0.5
                        NSLog("de-monitor: settled snapshot in cooldown, retrying in %.1fs", delay)
                        self.settleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                            Task { @MainActor in self?.snapshotWhenSettled(signal: signal, key: key, attempts: attempts - 1) }
                        }
                    } else {
                        NSLog("de-monitor: ignoring settled snapshot during post-apply cooldown")
                    }
                    return
                }
                // The port may have changed mid-settle: never file current
                // origins under a stale key.
                let fresh = Detector.detect()
                guard fresh.hasIdentity, fresh.key == key else {
                    NSLog("de-monitor: port changed or display removed during settle, dropping snapshot")
                    return
                }
                let second = LayoutApplier.currentOrigins()
                guard let first, let current = second.internalOrigin, second.external != nil,
                      Int(current.x) == Int(first.x), Int(current.y) == Int(first.y) else {
                    if attempts > 1 {
                        NSLog("de-monitor: arrangement still changing, retrying settle check")
                        self.snapshotWhenSettled(signal: fresh, key: key, attempts: attempts - 1)
                    } else {
                        NSLog("de-monitor: arrangement still changing, snapshot deferred")
                    }
                    return
                }
                self.snapshotCurrent(signal: fresh, key: key)
            }
        }
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

    private func makeStatusIcon() -> NSImage? {
        let size = NSSize(width: 29, height: 18)
        guard let monitor = NSImage(systemSymbolName: "display", accessibilityDescription: nil),
              let laptop = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: nil) else {
            return nil
        }
        let icon = NSImage(size: size)
        icon.lockFocus()
        monitor.draw(in: aspectFit(monitor.size, in: NSRect(x: 9, y: 1, width: 20, height: 15)))
        let laptopRect = aspectFit(laptop.size, in: NSRect(x: 3, y: 0.5, width: 16, height: 12))
        // Knock out monitor behind laptop so laptop reads as opaque.
        // Frame strokes and base bar are opaque and cover by overdraw;
        // only the hollow screen needs erasing. Pure geometric fill (no
        // image-alpha knockout) to avoid fringe notches at the edges.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSBezierPath(rect: NSRect(x: 6.5, y: 4.0, width: 8.5, height: 5.5)).fill()
        NSGraphicsContext.restoreGraphicsState()
        laptop.draw(in: laptopRect)
        icon.unlockFocus()
        return icon
    }

    private func aspectFit(_ inner: NSSize, in outer: NSRect) -> NSRect {
        guard inner.width > 0, inner.height > 0 else { return outer }
        let scale = min(outer.width / inner.width, outer.height / inner.height)
        let fitted = NSSize(width: inner.width * scale, height: inner.height * scale)
        return NSRect(
            x: outer.minX + (outer.width - fitted.width) / 2,
            y: outer.minY + (outer.height - fitted.height) / 2,
            width: fitted.width, height: fitted.height)
    }

    private func rebuildMenu(signal: PortSignal) {
        let menu = NSMenu()

        let title: String
        if signal.hasIdentity {
            let name = signal.productName ?? "External display"
            if let portType = signal.portType {
                title = "\(name) (\(portType))"
            } else {
                title = name
            }
        } else {
            title = "No external display"
        }
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if signal.hasIdentity, ProfileStore.load()[signal.key] != nil {
            let reset = NSMenuItem(title: "Reset configuration…",
                                   action: #selector(resetConfiguration), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
        }
        menu.addItem(.separator())

        let arrange = NSMenuItem(title: "Arrange Displays…",
                                 action: #selector(openArrangeDisplays), keyEquivalent: "")
        arrange.target = self
        menu.addItem(arrange)

        let autostart = NSMenuItem(title: "Start at login: \(Autostart.isEnabled ? "on" : "off")",
                                   action: #selector(toggleAutostart), keyEquivalent: "")
        autostart.target = self
        menu.addItem(autostart)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func openArrangeDisplays() {
        // Deep link into System Settings → Displays; there is no public
        // anchor for the arrange canvas itself, this is as close as it gets.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") else { return }
        NSWorkspace.shared.open(url, configuration: .init()) { _, error in
            if let error {
                NSLog("de-monitor: could not open Displays settings: %@", String(describing: error))
            }
        }
    }

    @objc private func resetConfiguration() {
        let signal = Detector.detect()
        guard signal.hasIdentity else { return }
        var setups = ProfileStore.load()
        guard setups.removeValue(forKey: signal.key) != nil else { return }
        do {
            try ProfileStore.save(setups)
            NSLog("de-monitor: configuration reset for %@", signal.key)
        } catch {
            NSLog("de-monitor: reset save failed: %@", String(describing: error))
        }
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
