import CoreGraphics
import Foundation

// Origin (0,0) makes a display the main one.
public struct DisplayProfile: Codable, Sendable, Equatable {
    public var internalOrigin: CGPointCodable

    public init(internalOrigin: CGPoint) {
        self.internalOrigin = CGPointCodable(internalOrigin)
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
