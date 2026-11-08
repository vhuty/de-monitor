import Testing
@testable import DisplaySwitcherCore

@Suite("Port type detection")
struct PortTypeTests {
    private func transport(
        _ portType: String?, product name: String? = nil, active: Bool = false
    ) -> Detector.TransportInfo {
        Detector.TransportInfo(portType: portType, portNumber: nil, productName: name, active: active)
    }

    @Test("parsedPortType handles USB-C, HDMI and unknowns")
    func parsedPortType() {
        #expect(Detector.parsedPortType(from: "Port-USB-C@2/DisplayPort") == "USB-C")
        #expect(Detector.parsedPortType(from: "Port-HDMI@1/DisplayPort") == "HDMI")
        #expect(Detector.parsedPortType(from: nil) == nil)
        #expect(Detector.parsedPortType(from: "Port-MagSafe 3@1/CC") == nil)
        #expect(Detector.parsedPortType(from: "SomethingElse") == nil)
    }

    @Test("exact ProductName match wins over active fallback")
    func exactMatchWins() {
        let transports = [
            transport("HDMI", product: "A", active: true),
            transport("USB-C", product: "MPG 274URF QD", active: false),
        ]
        #expect(Detector.resolvePortType(for: "MPG 274URF QD", transports: transports) == "USB-C")
    }

    @Test("HDMI vs Type-C are distinguished")
    func hdmiVsTypeC() {
        let hdmi = [transport("HDMI", product: "MPG 274URF QD", active: true)]
        let typeC = [transport("USB-C", product: "MPG 274URF QD", active: true)]
        #expect(Detector.resolvePortType(for: "MPG 274URF QD", transports: hdmi) == "HDMI")
        #expect(Detector.resolvePortType(for: "MPG 274URF QD", transports: typeC) == "USB-C")
    }

    @Test("unknown product falls back to the active transport")
    func fallbackToActive() {
        let transports = [
            transport("HDMI", active: false),
            transport("USB-C", active: true),
        ]
        #expect(Detector.resolvePortType(for: "Unknown", transports: transports) == "USB-C")
        #expect(Detector.resolvePortType(for: nil, transports: transports) == "USB-C")
    }

    @Test("no active transport returns nil, not a crash")
    func noActiveTransport() {
        #expect(Detector.resolvePortType(for: "X", transports: []) == nil)
        let inactive = [transport("USB-C", active: false)]
        // Single inactive entry: still reported so --detect shows something.
        #expect(Detector.resolvePortType(for: "X", transports: inactive) == "USB-C")
        let nameless = [Detector.TransportInfo(portType: nil, portNumber: nil, productName: nil, active: false)]
        #expect(Detector.resolvePortType(for: "X", transports: nameless) == nil)
    }

    @Test("portType never leaks into the setup key")
    func portTypeNotInKey() {
        let a = PortSignal(portID: 48, address: "0.3.0", productName: "X", portType: "HDMI")
        let b = PortSignal(portID: 48, address: "0.3.0", productName: "X", portType: "USB-C")
        #expect(a.key == b.key)
        #expect(a.key == "48/0.3.0")
    }
}
