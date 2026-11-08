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
        let transports = findDisplayPortTransports()

        // No external shim (e.g. lid closed / no monitor): still report
        // connection mapping if present so --detect shows something.
        if shims.isEmpty {
            let name = fallbackAddress?.productName
            return [PortSignal(portID: nil, address: fallbackAddress?.address,
                               productName: name,
                               portType: resolvePortType(for: name, transports: transports))]
        }
        return shims.map { shim in
            var address: String?
            if let name = shim.productName {
                address = addressByProduct[name]?.address
            }
            address = address ?? fallbackAddress?.address
            return PortSignal(portID: shim.portID, address: address,
                              productName: shim.productName,
                              portType: resolvePortType(for: shim.productName, transports: transports))
        }
    }

    /// Primary signal: first external shim, if any.
    public static func detect() -> PortSignal {
        detectAll().first ?? PortSignal()
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

    struct TransportInfo: Sendable {
        var portType: String?
        var portNumber: Int?
        var productName: String?
        var active: Bool
    }

    static func findDisplayPortTransports() -> [TransportInfo] {
        var out: [TransportInfo] = []
        guard let matching = IOServiceMatching("IOPortTransportStateDisplayPort") else { return out }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return out }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let current = service
            defer { IOObjectRelease(current) }
            let parentType = rawProp(current, "ParentPortTypeDescription") as? String
            let transportDescription = rawProp(current, "TransportDescription") as? String
            let portType = parentType ?? parsedPortType(from: transportDescription)
            out.append(TransportInfo(
                portType: portType,
                portNumber: numberToInt(rawProp(current, "ParentPortNumber")),
                productName: rawProp(current, "ProductName") as? String,
                active: numberToBool(rawProp(current, "Active"))
            ))
            service = IOIteratorNext(iterator)
        }
        return out
    }

    static func parsedPortType(from transportDescription: String?) -> String? {
        guard let d = transportDescription, d.hasPrefix("Port-") else { return nil }
        let rest = d.dropFirst("Port-".count)
        if rest.hasPrefix("USB-C") { return "USB-C" }
        if rest.hasPrefix("HDMI") { return "HDMI" }
        return nil
    }

    /// Pure join: shim ProductName -> transport portType, with fallback
    /// to the active transport (single-display case). Testable without IOKit.
    static func resolvePortType(for productName: String?, transports: [TransportInfo]) -> String? {
        let byProduct = Dictionary(
            uniqueKeysWithValues: transports.compactMap { t in
                t.productName.map { ($0, t) }
            }
        )
        if let name = productName, let t = byProduct[name] {
            return t.portType
        }
        return (transports.first(where: { $0.active }) ?? transports.first)?.portType
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

    static func numberToBool(_ value: Any?) -> Bool {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.intValue != 0
        case let n as Int: return n != 0
        default: return false
        }
    }

    static func rawProp(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(
            service, key as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as Any?
    }
}
