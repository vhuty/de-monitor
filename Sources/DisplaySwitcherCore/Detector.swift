import CoreFoundation
import Foundation
import IOKit

/// IOKit detection (read-only, no entitlements).
///
/// NOTE: The plan originally suggested `CGDisplayIOServicePort` ->
/// parent shim, but that API is marked unavailable in the macOS SDK
/// (`No longer supported`), so it cannot be called from Swift.
/// Instead we enumerate `IOMobileFramebufferShim` services directly:
/// the external monitor's shim is the one whose `DisplayAttributes`
/// dictionary contains a `PortID` key (the built-in panel's shim has
/// only `TiledDisplayInfo`, no `PortID`). `Address` comes from
/// `AppleDisplayConnectionManager.ConnectionMapping`, joined on
/// `ProductName`. With a single external display no CGDisplayID <->
/// io_service correlation is needed at all.
public enum Detector {
    /// All external shims found (normally 0 or 1 entries).
    public struct ShimInfo: Sendable {
        public var portID: Int
        public var productName: String?
    }

    public static func detectAll() -> [PortSignal] {
        let shims = findExternalShims()
        let addressByProduct = connectionAddressesByProduct()
        let fallbackAddress = connectionAddresses().first

        // No external shim (e.g. lid closed / no monitor): still report
        // connection mapping if present so --detect shows something.
        if shims.isEmpty {
            return [PortSignal(portID: nil, address: fallbackAddress?.address,
                               productName: fallbackAddress?.productName)]
        }
        return shims.map { shim in
            var address: String?
            if let name = shim.productName {
                address = addressByProduct[name]?.address
            }
            address = address ?? fallbackAddress?.address
            return PortSignal(portID: shim.portID, address: address,
                              productName: shim.productName)
        }
    }

    /// Primary signal: first external shim, if any.
    public static func detect() -> PortSignal {
        detectAll().first ?? PortSignal()
    }

    public static func classified() -> (signal: PortSignal, port: PhysicalPort) {
        let s = detect()
        return (s, classifyPort(signal: s))
    }

    // MARK: - Shim enumeration

    static func findExternalShims() -> [ShimInfo] {
        var out: [ShimInfo] = []
        guard let matching = IOServiceMatching("IOMobileFramebufferShim") else { return out }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return out }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let current = service
            defer { IOObjectRelease(current) }
            if let attrs = IORegistryEntryCreateCFProperty(
                service, "DisplayAttributes" as CFString,
                kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any],
               let portID = numberToInt(attrs["PortID"]) {
                let productName = (attrs["ProductAttributes"] as? [String: Any])?["ProductName"] as? String
                out.append(ShimInfo(portID: portID, productName: productName))
            }
            service = IOIteratorNext(iterator)
        }
        return out
    }

    // MARK: - Connection mapping

    struct CMEntry {
        var address: String?
        var productName: String?
    }

    static func connectionAddresses() -> [CMEntry] {
        var out: [CMEntry] = []
        guard let matching = IOServiceMatching("AppleDisplayConnectionManager") else { return out }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return out }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let current = service
            defer { IOObjectRelease(current) }
            if let mappings = IORegistryEntryCreateCFProperty(
                service, "ConnectionMapping" as CFString,
                kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [[String: Any]] {
                for m in mappings {
                    out.append(CMEntry(
                        address: m["Address"] as? String,
                        productName: m["ProductName"] as? String
                    ))
                }
            }
            service = IOIteratorNext(iterator)
        }
        return out
    }

    static func connectionAddressesByProduct() -> [String: CMEntry] {
        var dict: [String: CMEntry] = [:]
        for e in connectionAddresses() {
            if let name = e.productName {
                dict[name] = e
            }
        }
        return dict
    }

    // MARK: - Helpers

    static func numberToInt(_ value: Any?) -> Int? {
        switch value {
        case let n as Int: return n
        case let n as Int32: return Int(n)
        case let n as Int64: return Int(n)
        case let n as UInt: return Int(n)
        case let n as NSNumber: return n.intValue
        default: return nil
        }
    }
}
