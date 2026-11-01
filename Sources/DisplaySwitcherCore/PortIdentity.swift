import Foundation

/// Physical USB-C port group, per plan:
/// left ports (2x) -> one layout, right port (1x) -> another layout.
/// Pattern from A-B-A replug test: Address = 0.{N}.0, PortID = 16*N.
public enum PhysicalPort: String, Codable, Sendable, CaseIterable {
    case left
    case right
    case unknown

    public var displayName: String {
        switch self {
        case .left: "Left USB-C"
        case .right: "Right USB-C"
        case .unknown: "Unknown port"
        }
    }
}

/// Raw IOKit signal read from the external monitor's shim + connection mapping.
public struct PortSignal: Sendable, Equatable {
    public var portID: Int?
    public var address: String?
    public var productName: String?

    public init(portID: Int? = nil, address: String? = nil, productName: String? = nil) {
        self.portID = portID
        self.address = address
        self.productName = productName
    }
}

/// Classify (PortID, Address) pair into a physical port.
///
/// Known table (plan, verified twice for right, once per left port):
/// | Left #1 | PortID 0  | 0.0.0 |
/// | Left #2 | PortID 16 | 0.1.0 |
/// | Right   | PortID 32 | 0.2.0 |
public func classifyPort(signal: PortSignal) -> PhysicalPort {
    // Exact known pairs first.
    if signal.portID == 32 || signal.address == "0.2.0" {
        return .right
    }
    if signal.portID == 0 || signal.portID == 16
        || signal.address == "0.0.0" || signal.address == "0.1.0" {
        return .left
    }
    // Generic pattern fallback: PortID = 16*N, Address = 0.N.0.
    // N=0,1 -> left cluster; N=2 -> right. Unknown N -> unknown (graceful).
    if let portID = signal.portID, portID % 16 == 0 {
        switch portID / 16 {
        case 0, 1: return .left
        case 2: return .right
        default: break
        }
    }
    if let address = signal.address {
        let parts = address.split(separator: ".")
        if parts.count == 3, parts.first == "0", parts.last == "0", let n = Int(parts[1]) {
            switch n {
            case 0, 1: return .left
            case 2: return .right
            default: break
            }
        }
    }
    return .unknown
}
