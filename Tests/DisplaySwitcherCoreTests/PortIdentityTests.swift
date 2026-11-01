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

    @Test("default layouts match measured hardware")
    func defaultLayouts() {
        let layouts = PortLayouts.defaults()
        #expect(layouts.right.internalOrigin == CGPointCodable(x: -1512, y: 278))
        #expect(layouts.profile(for: .left).internalOrigin.x == 524)
        #expect(layouts.profile(for: .unknown) == layouts.right)
    }
}
