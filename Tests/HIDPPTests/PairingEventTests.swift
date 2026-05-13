import Testing
@testable import HIDPP

@Suite("PairingEvent decoding")
struct PairingEventTests {

    private func short(deviceIndex: UInt8, subID: UInt8, address: UInt8, params: [UInt8]) -> HIDPPReport {
        HIDPPReport(kind: .short, deviceIndex: deviceIndex, subID: subID, address: address, parameters: params)
    }

    @Test("0x4A with address bit 0 set → lockOpened")
    func lockOpened() {
        let r = short(deviceIndex: 0xFF, subID: 0x4A, address: 0x01, params: [0x00, 0x00, 0x00])
        if case .lockOpened = PairingEvent.decode(r) { } else { Issue.record("expected lockOpened") }
    }

    @Test("0x4A with address bit 0 clear, no error → lockClosed success")
    func lockClosedClean() {
        let r = short(deviceIndex: 0xFF, subID: 0x4A, address: 0x00, params: [0x00, 0x00, 0x00])
        if case .lockClosed(let success, let code) = PairingEvent.decode(r) {
            #expect(success == true)
            #expect(code == nil)
        } else { Issue.record("expected lockClosed") }
    }

    @Test("0x4A with non-zero pair-error byte → lockClosed failure with code")
    func lockClosedError() {
        let r = short(deviceIndex: 0xFF, subID: 0x4A, address: 0x00, params: [0x06, 0x00, 0x00])
        if case .lockClosed(let success, let code) = PairingEvent.decode(r) {
            #expect(success == false)
            #expect(code == 0x06)
        } else { Issue.record("expected lockClosed with error") }
    }

    @Test("0x41 to slot 1 with mouse kind nibble → deviceConnected")
    func deviceConnectedMouse() {
        // params[0] low-nibble = 2 (mouse), high-nibble = link status
        // params[1..2] = WPID big-endian
        let r = short(deviceIndex: 0x01, subID: 0x41, address: 0x00, params: [0x02, 0x40, 0x02])
        if case .deviceConnected(let slot, let wpid, let kind) = PairingEvent.decode(r) {
            #expect(slot == 1)
            #expect(kind == .mouse)
            #expect(wpid == 0x4002)
        } else { Issue.record("expected deviceConnected") }
    }

    @Test("0x40 to slot 3 → deviceDisconnected")
    func deviceDisconnected() {
        let r = short(deviceIndex: 0x03, subID: 0x40, address: 0x00, params: [0x00, 0x00, 0x00])
        if case .deviceDisconnected(let slot) = PairingEvent.decode(r) {
            #expect(slot == 3)
        } else { Issue.record("expected deviceDisconnected") }
    }

    @Test("Unknown notification falls through to .raw")
    func rawFallthrough() {
        let r = short(deviceIndex: 0xFF, subID: 0x99, address: 0x00, params: [0x00, 0x00, 0x00])
        if case .raw = PairingEvent.decode(r) { } else { Issue.record("expected raw") }
    }
}
