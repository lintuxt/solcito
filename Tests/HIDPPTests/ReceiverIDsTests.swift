import Testing
@testable import HIDPP

@Suite("KnownReceivers lookup")
struct ReceiverIDsTests {

    @Test("Unifying receiver C52B classifies as .unifying")
    func unifyingLookup() {
        let id = KnownReceivers.lookup(vendorID: 0x046D, productID: 0xC52B)
        #expect(id?.kind == .unifying)
        #expect(id?.name == "Unifying Receiver")
    }

    @Test("Bolt receiver C548 classifies as .bolt")
    func boltLookup() {
        let id = KnownReceivers.lookup(vendorID: 0x046D, productID: 0xC548)
        #expect(id?.kind == .bolt)
    }

    @Test("Lenovo-branded nano uses Lenovo VID, not Logitech VID")
    func lenovoNanoUsesLenovoVID() {
        #expect(KnownReceivers.lookup(vendorID: 0x046D, productID: 0x6042) == nil)
        let id = KnownReceivers.lookup(vendorID: 0x17EF, productID: 0x6042)
        #expect(id?.kind == .nano)
    }

    @Test("Unknown PID returns nil")
    func unknownLookup() {
        #expect(KnownReceivers.lookup(vendorID: 0x046D, productID: 0xFFFF) == nil)
    }

    @Test("Vendor IDs include both Logitech and Lenovo")
    func vendorIDsScanned() {
        let vids = KnownReceivers.allVendorIDs
        #expect(vids.contains(0x046D))
        #expect(vids.contains(0x17EF))
    }

    @Test("Pairing capability matches receiver kind")
    func pairingCapability() {
        #expect(ReceiverKind.unifying.supportsPairing)
        #expect(ReceiverKind.bolt.supportsPairing)
        #expect(ReceiverKind.lightspeed.supportsPairing)
        #expect(!ReceiverKind.nano.supportsPairing)
        #expect(!ReceiverKind.ex100_27mhz.supportsPairing)
    }
}
