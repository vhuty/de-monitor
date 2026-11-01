import CoreGraphics
import Foundation

/// Applies display arrangements via CoreGraphics transactions
/// (same mechanism as displayplacer: Begin -> ConfigureOrigin x2 -> Complete).
public enum LayoutApplier {
    public struct DisplayInfo: Sendable {
        public var id: CGDirectDisplayID
        public var isBuiltin: Bool
        public var isMain: Bool
        public var bounds: CGRect
    }

    public static func activeDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map {
            DisplayInfo(id: $0, isBuiltin: CGDisplayIsBuiltin($0) != 0,
                        isMain: CGDisplayIsMain($0) != 0, bounds: CGDisplayBounds($0))
        }
    }

    /// Current origins keyed by kind, for `remember current` support.
    public static func currentOrigins() -> (internalOrigin: CGPoint?, external: CGPoint?) {
        let displays = activeDisplays()
        let internalOrigin = displays.first(where: { $0.isBuiltin }).map { $0.bounds.origin }
        let externalOrigin = displays.first(where: { !$0.isBuiltin }).map { $0.bounds.origin }
        return (internalOrigin, externalOrigin)
    }

    /// True when both displays already sit at the profile's origins
    /// (external at (0,0) = main, internal at the profile origin).
    /// Lets callers skip a redundant reconfiguration (which always
    /// flickers: system fade + monitor resync).
    public static func matches(_ profile: DisplayProfile) -> Bool {
        let displays = activeDisplays()
        guard let internalDisplay = displays.first(where: { $0.isBuiltin }),
              let externalDisplay = displays.first(where: { !$0.isBuiltin }) else {
            return false
        }
        let io = internalDisplay.bounds.origin
        let eo = externalDisplay.bounds.origin
        return Int(eo.x) == 0 && Int(eo.y) == 0
            && Int(io.x) == profile.internalOrigin.x
            && Int(io.y) == profile.internalOrigin.y
    }

    @discardableResult
    public static func apply(_ profile: DisplayProfile) -> Bool {
        let displays = activeDisplays()
        guard let internalDisplay = displays.first(where: { $0.isBuiltin }),
              let externalDisplay = displays.first(where: { !$0.isBuiltin }) else {
            return false // single-display (docked closed / no external): nothing to arrange
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        // External at (0,0) -> becomes main display.
        var ok = CGConfigureDisplayOrigin(config, externalDisplay.id, 0, 0) == .success
        ok = ok && (CGConfigureDisplayOrigin(
            config, internalDisplay.id,
            Int32(profile.internalOrigin.x), Int32(profile.internalOrigin.y)) == .success)
        guard ok else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    /// displayplacer-style one-liner for the current state (for README parity).
    public static func describeCurrent() -> String {
        activeDisplays().map { d in
            "\(d.isBuiltin ? "internal" : "external") id=\(d.id)"
                + " origin=(\(Int(d.bounds.origin.x)),\(Int(d.bounds.origin.y)))"
                + (d.isMain ? " main" : "")
        }.joined(separator: "\n")
    }
}
