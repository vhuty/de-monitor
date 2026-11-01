import CoreGraphics
import Foundation

/// A display arrangement: origin of the internal (built-in) panel.
/// The external monitor is always placed at (0,0), which per
/// displayplacer behavior makes it the main display ("white bar").
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

/// Per-port layout mapping.
public struct PortLayouts: Codable, Sendable {
    public var left: DisplayProfile
    public var right: DisplayProfile
    /// Layout applied when the port can't be identified (manual fallback).
    public var fallback: DisplayProfile

    public init(left: DisplayProfile, right: DisplayProfile, fallback: DisplayProfile? = nil) {
        self.left = left
        self.right = right
        self.fallback = fallback ?? right
    }

    public func profile(for port: PhysicalPort) -> DisplayProfile {
        switch port {
        case .left: left
        case .right: right
        case .unknown: fallback
        }
    }

    /// Factory defaults from measured hardware:
    /// - right port (current `displayplacer list`): laptop left of monitor,
    ///   internal at (-1512,278).
    /// - left port ("below", monitor on top centered over 1512-wide panel):
    ///   external 2560 wide -> x = (2560-1512)/2 = 524, y = 1440.
    ///   User-tunable via `remember` / menu-bar picker.
    public static func defaults() -> PortLayouts {
        PortLayouts(
            left: DisplayProfile(
                internalOrigin: CGPoint(x: 524, y: 1440),
                note: "laptop under monitor (default centered)"),
            right: DisplayProfile(
                internalOrigin: CGPoint(x: -1512, y: 278),
                note: "laptop left of monitor (measured)")
        )
    }
}
