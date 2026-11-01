import Foundation

// Opaque port identity: used as-is to key saved setups, never interpreted.
public struct PortSignal: Sendable, Equatable {
    public var portID: Int?
    public var address: String?
    public var productName: String?

    public init(portID: Int? = nil, address: String? = nil, productName: String? = nil) {
        self.portID = portID
        self.address = address
        self.productName = productName
    }

    /// Stable key for saved setups. Empty when no port is identifiable
    /// (no external display).
    public var key: String {
        switch (portID, address) {
        case let (id?, addr?): "\(id)/\(addr)"
        case let (id?, nil): "\(id)"
        case let (nil, addr?): addr
        default: ""
        }
    }

    public var hasIdentity: Bool { !key.isEmpty }
}
