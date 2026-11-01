import DisplaySwitcherCore
import Foundation

func printUsage() {
    print("""
    de-monitor — USB-C port display switcher
    Usage:
      de-monitor --detect              print (PortID, Address) -> port
      de-monitor --status               detect + current layout + configured profiles
      de-monitor --apply [left|right] [--force]  apply layout (default: auto by port; skips if already active)
      de-monitor --remember [left|right] save current internal origin as that port's layout
      de-monitor --list                 show current display origins
    """)
}

let args = CommandLine.arguments.dropFirst()

guard let cmd = args.first else {
    printUsage()
    exit(2)
}

switch cmd {
case "--detect":
    let (signal, port) = Detector.classified()
    print("PortID: \(signal.portID.map(String.init) ?? "nil")")
    print("Address: \(signal.address ?? "nil")")
    print("Product: \(signal.productName ?? "nil")")
    print("Port: \(port.rawValue) (\(port.displayName))")

case "--status":
    let (signal, port) = Detector.classified()
    print("PortID: \(signal.portID.map(String.init) ?? "nil")  Address: \(signal.address ?? "nil")  -> \(port.rawValue)")
    print("--- current ---")
    print(LayoutApplier.describeCurrent())
    let stored = ProfileStore.load()
    print("--- profiles (\(ProfileStore.configURL.path)) ---")
    print("left:  (\(stored.layouts.left.internalOrigin.x),\(stored.layouts.left.internalOrigin.y)) \(stored.layouts.left.note)")
    print("right: (\(stored.layouts.right.internalOrigin.x),\(stored.layouts.right.internalOrigin.y)) \(stored.layouts.right.note)")

case "--list":
    print(LayoutApplier.describeCurrent())

case "--apply":
    let stored = ProfileStore.load()
    let rest = Array(args.dropFirst())
    let force = rest.contains("--force")
    let port: PhysicalPort
    if let name = rest.first(where: { $0 != "--force" }), let p = PhysicalPort(rawValue: name) {
        port = p
    } else {
        port = Detector.classified().port
    }
    let profile = stored.layouts.profile(for: port)
    if !force && LayoutApplier.matches(profile) {
        print("\(port.rawValue) layout already active: internal (\(profile.internalOrigin.x),\(profile.internalOrigin.y)) — skipping (use --force to re-apply)")
        break
    }
    print("Applying \(port.rawValue) layout: internal (\(profile.internalOrigin.x),\(profile.internalOrigin.y)) ...")
    if LayoutApplier.apply(profile) {
        print("OK")
    } else {
        print("FAILED (need 2 active displays?)")
        exit(1)
    }

case "--remember":
    var stored = ProfileStore.load()
    let port: PhysicalPort
    if let name = args.dropFirst().first, let p = PhysicalPort(rawValue: name), p != .unknown {
        port = p
    } else {
        port = Detector.classified().port
        if port == .unknown {
            print("Cannot determine port; specify: --remember [left|right]")
            exit(1)
        }
    }
    guard let origin = LayoutApplier.currentOrigins().internalOrigin else {
        print("No internal display found.")
        exit(1)
    }
    let profile = DisplayProfile(internalOrigin: origin, note: "remembered \(Date())")
    switch port {
    case .left: stored.layouts.left = profile
    case .right: stored.layouts.right = profile
    case .unknown: break
    }
    do {
        try ProfileStore.save(stored)
        print("Remembered \(port.rawValue): internal (\(Int(origin.x)),\(Int(origin.y)))")
    } catch {
        print("Save failed: \(error)")
        exit(1)
    }

case "--help", "-h", "help":
    printUsage()

default:
    print("Unknown command: \(cmd)\n")
    printUsage()
    exit(2)
}
