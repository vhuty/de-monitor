import CoreGraphics
import Foundation

// Origin (0,0) makes a display the main one.
public struct DisplayProfile: Codable, Sendable, Equatable {
    public var internalOrigin: CGPointCodable
    public var note: String

    public init(internalOrigin: CGPoint, note: String = "") {
        self.internalOrigin = CGPointCodable(internalOrigin)
        self.note = note
    }
}

public struct CGPointCodable: Codable, Sendable, Equatable {
    public var x: Int
    public var y: Int

    public init(_ p: CGPoint) {
        self.x = Int(p.x)
        self.y = Int(p.y)
    }

    public init(x: Int, y: Int) {
        self.x = x; self.y = y
    }

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

// Nil profile = port not configured yet; nothing is auto-applied for it.
public struct PortLayouts: Codable, Sendable, Equatable {
    public var left: DisplayProfile?
    public var right: DisplayProfile?

    public init(left: DisplayProfile? = nil, right: DisplayProfile? = nil) {
        self.left = left
        self.right = right
    }

    public func profile(for port: PhysicalPort) -> DisplayProfile? {
        switch port {
        case .left: left
        case .right: right
        case .unknown: nil
        }
    }
}
