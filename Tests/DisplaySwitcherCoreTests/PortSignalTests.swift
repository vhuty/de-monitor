import CoreGraphics
import Foundation
import Testing
@testable import DisplaySwitcherCore

@Suite("Opaque port identity")
struct PortSignalTests {
    @Test("key is stable and distinctive")
    func keyStability() {
        let a = PortSignal(portID: 32, address: "0.2.0", productName: "X")
        let b = PortSignal(portID: 32, address: "0.2.0", productName: "Y")
        #expect(a.key == b.key)
        #expect(a.key != PortSignal(portID: 16, address: "0.1.0").key)
        #expect(a.key != PortSignal(portID: 32, address: nil).key)
        #expect(a.hasIdentity)
        #expect(PortSignal().hasIdentity == false)
    }

    @Test("setups survive a JSON round-trip")
    func jsonRoundTrip() throws {
        let setups: [String: DisplayProfile] = [
            "32/0.2.0": DisplayProfile(internalOrigin: CGPoint(x: -1512, y: 278)),
        ]
        let data = try JSONEncoder().encode(setups)
        let decoded = try JSONDecoder().decode([String: DisplayProfile].self, from: data)
        #expect(decoded == setups)
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
