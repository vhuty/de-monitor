import DisplaySwitcherCore
import Foundation

func printUsage() {
    print("""
    de-monitor — USB-C port display switcher
    Usage:
      de-monitor --detect              print PortID/Address/product/port key
      de-monitor --status               detect + current layout + saved setups
      de-monitor --apply [port-key] [--force]  restore setup (default: current port)
      de-monitor --remember             save current arrangement for the current port
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
    let signal = Detector.detect()
    print("PortID: \(signal.portID.map(String.init) ?? "nil")")
    print("Address: \(signal.address ?? "nil")")
    print("Product: \(signal.productName ?? "nil")")
    print("Key: \(signal.hasIdentity ? signal.key : "(no port)")")

case "--status":
    let signal = Detector.detect()
    print("PortID: \(signal.portID.map(String.init) ?? "nil")  Address: \(signal.address ?? "nil")")
    print("--- current ---")
    print(LayoutApplier.describeCurrent())
    let setups = ProfileStore.load()
    print("--- saved setups (\(ProfileStore.configURL.path)) ---")
    if setups.isEmpty {
        print("none saved yet (arrange in Settings, then --remember)")
    } else {
        for key in setups.keys.sorted() {
            let p = setups[key]!
            print("\(key): internal (\(p.internalOrigin.x),\(p.internalOrigin.y))")
        }
    }

case "--list":
    print(LayoutApplier.describeCurrent())

case "--apply":
    let setups = ProfileStore.load()
    let rest = Array(args.dropFirst())
    let force = rest.contains("--force")
    let key: String
    if let explicit = rest.first(where: { $0 != "--force" }) {
        key = explicit
    } else {
        let signal = Detector.detect()
        guard signal.hasIdentity else {
            print("No external display detected.")
            exit(1)
        }
        key = signal.key
    }
    guard let profile = setups[key] else {
        print("No saved setup for \(key) — arrange displays in System Settings, then `de-monitor --remember`")
        exit(1)
    }
    if !force && LayoutApplier.matches(profile) {
        print("\(key) already active: internal (\(profile.internalOrigin.x),\(profile.internalOrigin.y)) — skipping (use --force to re-apply)")
        break
    }
    print("Applying \(key): internal (\(profile.internalOrigin.x),\(profile.internalOrigin.y)) ...")
    if LayoutApplier.apply(profile) {
        print("OK")
    } else {
        print("FAILED (need 2 active displays?)")
        exit(1)
    }

case "--remember":
    let signal = Detector.detect()
    guard signal.hasIdentity else {
        print("No external display detected.")
        exit(1)
    }
    guard let origin = LayoutApplier.currentOrigins().internalOrigin else {
        print("No internal display found.")
        exit(1)
    }
    var setups = ProfileStore.load()
    setups[signal.key] = DisplayProfile(internalOrigin: origin)
    do {
        try ProfileStore.save(setups)
        print("Remembered \(signal.key): internal (\(Int(origin.x)),\(Int(origin.y)))")
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
