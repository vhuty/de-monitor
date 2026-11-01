import CoreGraphics
import Foundation
import Testing
@testable import DisplaySwitcherCore

@Suite("Port classification (A-B-A replug table)")
struct PortIdentityTests {
    @Test("known pairs")
    func knownPairs() {
        #expect(classifyPort(signal: PortSignal(portID: 0, address: "0.0.0")) == .left)
        #expect(classifyPort(signal: PortSignal(portID: 16, address: "0.1.0")) == .left)
        #expect(classifyPort(signal: PortSignal(portID: 32, address: "0.2.0")) == .right)
    }

    @Test("single-signal classification")
    func singleSignal() {
        #expect(classifyPort(signal: PortSignal(portID: 32, address: nil)) == .right)
        #expect(classifyPort(signal: PortSignal(portID: nil, address: "0.2.0")) == .right)
        #expect(classifyPort(signal: PortSignal(portID: 0, address: nil)) == .left)
        #expect(classifyPort(signal: PortSignal(portID: 16, address: nil)) == .left)
        #expect(classifyPort(signal: PortSignal(portID: nil, address: "0.1.0")) == .left)
    }

    @Test("pattern fallback 16*N / 0.N.0")
    func patternFallback() {
        #expect(classifyPort(signal: PortSignal(portID: 48, address: nil)) == .unknown)
        #expect(classifyPort(signal: PortSignal(portID: nil, address: "0.3.0")) == .unknown)
        #expect(classifyPort(signal: PortSignal(portID: nil, address: nil)) == .unknown)
        #expect(classifyPort(signal: PortSignal(portID: 7, address: "bogus")) == .unknown)
    }

    @Test("empty layouts: nothing configured")
    func emptyLayouts() {
        let layouts = PortLayouts()
        #expect(layouts.left == nil)
        #expect(layouts.right == nil)
        #expect(layouts.profile(for: .left) == nil)
        #expect(layouts.profile(for: .right) == nil)
        #expect(layouts.profile(for: .unknown) == nil)
    }

    @Test("layouts survive a JSON round-trip")
    func jsonRoundTrip() throws {
        let layouts = PortLayouts(
            left: DisplayProfile(internalOrigin: CGPoint(x: 1, y: 2), note: "n"))
        let data = try JSONEncoder().encode(layouts)
        let decoded = try JSONDecoder().decode(PortLayouts.self, from: data)
        #expect(decoded == layouts)
    }

    @Test("matches() reflects the live arrangement")
    func matchesLiveArrangement() {
        let origins = LayoutApplier.currentOrigins()
        guard let io = origins.internalOrigin, origins.external != nil else {
            return
        }
        #expect(LayoutApplier.matches(DisplayProfile(internalOrigin: io)) == (Int(origins.external!.x) == 0 && Int(origins.external!.y) == 0))
        let shifted = DisplayProfile(internalOrigin: CGPoint(x: io.x + 1, y: io.y))
        #expect(LayoutApplier.matches(shifted) == false)
    }
}
