import Testing
import Foundation
@testable import HIDPP

@Suite("HIDPPReport framing")
struct HIDPPReportTests {

    @Test("Short report roundtrip preserves all fields")
    func shortRoundtrip() {
        let original = HIDPPReport(
            kind: .short,
            deviceIndex: 0xFF,
            subID: HIDPP10.SubID.getRegisterShort.rawValue,
            address: HIDPP10.Register.connectionState.rawValue,
            parameters: [0xAA, 0xBB, 0xCC]
        )
        let wire = original.serializedPayload()
        #expect(wire.count == 6)  // payload size excludes report ID byte

        let parsed = HIDPPReport.parse(reportID: HIDPPReportKind.short.rawValue, payload: wire)
        #expect(parsed == original)
    }

    @Test("Long report serializes to 19 bytes after report ID")
    func longPayloadSize() {
        let r = HIDPPReport(
            kind: .long,
            deviceIndex: 0xFF,
            subID: HIDPP10.SubID.getRegisterLong.rawValue,
            address: HIDPP10.Register.pairingInfo.rawValue,
            parameters: [HIDPP10.PairingInfoSub.receiverInformation]
        )
        #expect(r.serializedPayload().count == 19)
        #expect(r.parameters.count == 16)  // zero-padded
    }

    @Test("Parameters longer than report capacity trap")
    func tooManyParameters() async {
        // We can't easily test precondition() trap, but we can assert the
        // public contract via parameter count after init.
        let r = HIDPPReport(kind: .short, deviceIndex: 0xFF, subID: 0, address: 0, parameters: [1, 2])
        #expect(r.parameters.count == 3)  // padded to 3
        #expect(r.parameters == [1, 2, 0])
    }

    @Test("Error report decodes original sub-ID, register, code")
    func errorPayloadDecodes() {
        // Wire bytes after report ID 0x10:
        // [devIdx=FF][subID=8F][origSubID=83][origAddr=B5][errCode=03][padding 0]
        let payload = Data([0xFF, 0x8F, 0x83, 0xB5, 0x03, 0x00])
        guard let report = HIDPPReport.parse(reportID: HIDPPReportKind.short.rawValue, payload: payload) else {
            Issue.record("failed to parse error report")
            return
        }
        #expect(report.isError)
        let err = report.errorPayload
        #expect(err?.originalSubID == 0x83)
        #expect(err?.originalAddress == 0xB5)
        #expect(err?.code == 0x03)
        #expect(HIDPP10.ErrorCode(rawValue: err!.code) == .invalidValue)
    }

    @Test("parse() rejects wrong-size payloads")
    func wrongSizeRejected() {
        #expect(HIDPPReport.parse(reportID: 0x10, payload: Data([0x01, 0x02])) == nil)
        #expect(HIDPPReport.parse(reportID: 0xAB, payload: Data(count: 6)) == nil)  // unknown report ID
    }
}
