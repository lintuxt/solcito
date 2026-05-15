import Testing
@testable import HIDPP

@Suite("DeviceDetails byte parsers")
struct DeviceDetailsTests {

    // Captured from a real pairing trace: receiver volunteered the slot-2
    // device name as a long-register response with sub-address echo 0x41.
    //   raw payload after stripping report ID + dev + sub + addr:
    //     params = [41 07 4D 58 20 45 72 67 6F 00 00 00 00 00 00 00]
    // → name length 7, ASCII "MX Ergo".
    @Test("device-name parser decodes MX Ergo from real bytes")
    func deviceNameRealBytes() {
        let params: [UInt8] = [0x41, 0x07,
                               0x4D, 0x58, 0x20, 0x45, 0x72, 0x67, 0x6F,
                               0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        let name = DeviceDetails.parseDeviceName(parameters: params, expectedSub: 0x41)
        #expect(name == "MX Ergo")
    }

    @Test("device-name parser returns nil on wrong sub-address echo")
    func deviceNameWrongSub() {
        let params: [UInt8] = [0x42, 0x03, 0x41, 0x42, 0x43] + Array(repeating: 0, count: 11)
        #expect(DeviceDetails.parseDeviceName(parameters: params, expectedSub: 0x41) == nil)
    }

    @Test("device-name parser returns nil when length is zero")
    func deviceNameZeroLength() {
        let params: [UInt8] = [0x41, 0x00] + Array(repeating: 0, count: 14)
        #expect(DeviceDetails.parseDeviceName(parameters: params, expectedSub: 0x41) == nil)
    }

    @Test("pairing-info parser extracts WPID + kind")
    func pairingInfoBasic() {
        // sub-echo=0x21, then six unused bytes, then byte 7 = device-kind
        // nibble. WPID lives at params[3..4].
        var params = Array<UInt8>(repeating: 0, count: 16)
        params[0] = 0x21
        params[3] = 0x40   // WPID hi
        params[4] = 0x6F   // WPID lo
        params[7] = 0x08   // kind = trackball
        let info = DeviceDetails.parsePairingInfo(parameters: params, expectedSub: 0x21)
        #expect(info?.wpid == 0x406F)
        #expect(info?.kind == .trackball)
    }

    @Test("pairing-info parser nils out WPID == 0")
    func pairingInfoZeroWPID() {
        var params = Array<UInt8>(repeating: 0, count: 16)
        params[0] = 0x21
        params[7] = 0x02
        let info = DeviceDetails.parsePairingInfo(parameters: params, expectedSub: 0x21)
        #expect(info?.wpid == nil)
        #expect(info?.kind == .mouse)
    }

    @Test("formatDeviceLabel renders by what's known")
    func labelFallbacks() {
        let full = DeviceDetails(slot: 2, name: "MX Ergo", kind: .trackball, wpid: 0x406F)
        #expect(formatDeviceLabel(full) == "MX Ergo (Trackball)")

        let nameOnly = DeviceDetails(slot: 2, name: "MX Ergo", kind: nil, wpid: nil)
        #expect(formatDeviceLabel(nameOnly) == "MX Ergo")

        let kindOnly = DeviceDetails(slot: 2, name: nil, kind: .trackball, wpid: nil)
        #expect(formatDeviceLabel(kindOnly) == "Trackball")

        let wpidHit = DeviceDetails(slot: 2, name: nil, kind: nil, wpid: 0x4082)
        #expect(formatDeviceLabel(wpidHit) == "MX Master 3 Mouse")

        let empty = DeviceDetails(slot: 2)
        #expect(formatDeviceLabel(empty) == "paired")

        // De-dup: name already contains the kind word, drop the parenthetical
        let already = DeviceDetails(slot: 2, name: "MX Ergo Multi-Device Trackball", kind: .trackball, wpid: nil)
        #expect(formatDeviceLabel(already) == "MX Ergo Multi-Device Trackball")
    }

    @Test("UnifiedBattery: percent at byte 0, charging flag at byte 2")
    func unifiedBatteryDischarging() {
        let p: [UInt8] = [0x4E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        let r = DeviceDetails.parseUnifiedBattery(parameters: p)
        #expect(r?.percent == 78)
        #expect(r?.isCharging == false)
    }

    @Test("UnifiedBattery: non-zero status byte = charging")
    func unifiedBatteryCharging() {
        let p: [UInt8] = [0x5A, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        let r = DeviceDetails.parseUnifiedBattery(parameters: p)
        #expect(r?.percent == 90)
        #expect(r?.isCharging == true)
    }

    @Test("UnifiedBattery: percent above 100 rejected")
    func unifiedBatteryGarbage() {
        let p: [UInt8] = [0xFF, 0x00, 0x00] + Array(repeating: 0, count: 13)
        #expect(DeviceDetails.parseUnifiedBattery(parameters: p) == nil)
    }

    @Test("LegacyBattery: discharging when status == 0")
    func legacyBatteryDischarging() {
        let p: [UInt8] = [0x32, 0x00, 0x00] + Array(repeating: 0, count: 13)
        let r = DeviceDetails.parseLegacyBattery(parameters: p)
        #expect(r?.percent == 50)
        #expect(r?.isCharging == false)
    }

    @Test("LegacyBattery: charging when status is 1 or 2")
    func legacyBatteryCharging() {
        let recharging: [UInt8] = [0x64, 0x00, 0x01] + Array(repeating: 0, count: 13)
        #expect(DeviceDetails.parseLegacyBattery(parameters: recharging)?.isCharging == true)
        let charged: [UInt8] = [0x64, 0x00, 0x02] + Array(repeating: 0, count: 13)
        #expect(DeviceDetails.parseLegacyBattery(parameters: charged)?.isCharging == true)
        let failed: [UInt8] = [0x64, 0x00, 0x03] + Array(repeating: 0, count: 13)
        #expect(DeviceDetails.parseLegacyBattery(parameters: failed)?.isCharging == false)
    }
}
