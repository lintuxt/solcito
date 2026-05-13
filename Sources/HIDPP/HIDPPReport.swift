import Foundation

/// HID++ has two report sizes. The chosen size depends on whether we need to
/// carry 3 or 16 parameter bytes — short for most simple register ops, long
/// for receiver-info reads and pairing notifications.
public enum HIDPPReportKind: UInt8, Sendable {
    case short = 0x10
    case long  = 0x11

    public var totalSize: Int {
        switch self {
        case .short: return 7   // 1 (reportID) + 1 (devIdx) + 1 (subID) + 1 (addr) + 3 params
        case .long:  return 20  // 1 + 1 + 1 + 1 + 16 params
        }
    }

    public var payloadSize: Int { totalSize - 1 }     // excludes report ID byte
    public var parameterCount: Int { totalSize - 4 }  // 3 or 16
}

/// Decoded HID++ report. The on-the-wire layout is:
///
///     [report ID][device index][sub ID][address/feature index][parameters...]
///
/// For receiver-bound traffic, `deviceIndex == 0xFF`. For HID++ 1.0 register
/// ops, `subID` selects the operation (e.g. 0x83 = get-long-register) and
/// `address` is the register byte. Error responses use `subID == 0x8F`; see
/// `errorPayload`.
public struct HIDPPReport: Sendable, Hashable, CustomStringConvertible {

    public static let receiverDeviceIndex: UInt8 = 0xFF

    public let kind: HIDPPReportKind
    public let deviceIndex: UInt8
    public let subID: UInt8
    public let address: UInt8
    public let parameters: [UInt8]

    public init(kind: HIDPPReportKind, deviceIndex: UInt8, subID: UInt8, address: UInt8, parameters: [UInt8]) {
        precondition(parameters.count <= kind.parameterCount,
                     "too many parameters for \(kind) report")
        self.kind = kind
        self.deviceIndex = deviceIndex
        self.subID = subID
        self.address = address
        var padded = parameters
        while padded.count < kind.parameterCount { padded.append(0) }
        self.parameters = padded
    }

    /// Wire-format payload that goes after the report ID byte. Length is
    /// `kind.payloadSize` (6 for short, 19 for long).
    public func serializedPayload() -> Data {
        var bytes: [UInt8] = [deviceIndex, subID, address]
        bytes.append(contentsOf: parameters)
        return Data(bytes)
    }

    /// Parse a raw input report. `payload` is everything after the report ID
    /// byte. Returns nil if the byte count doesn't match either HID++ size.
    public static func parse(reportID: UInt8, payload: Data) -> HIDPPReport? {
        guard let kind = HIDPPReportKind(rawValue: reportID) else { return nil }
        guard payload.count >= kind.payloadSize else { return nil }
        let bytes = [UInt8](payload.prefix(kind.payloadSize))
        return HIDPPReport(
            kind: kind,
            deviceIndex: bytes[0],
            subID: bytes[1],
            address: bytes[2],
            parameters: Array(bytes[3..<kind.payloadSize])
        )
    }

    /// True iff this report represents a protocol error message.
    /// HID++ 1.0 marks errors with sub-ID 0x8F; HID++ 2.0 with 0xFF.
    public var isError: Bool { subID == 0x8F || subID == 0xFF }

    /// For an error report, decodes the (original sub-ID, original register,
    /// error code) triple. Returns nil for non-error reports.
    public var errorPayload: (originalSubID: UInt8, originalAddress: UInt8, code: UInt8)? {
        guard isError, parameters.count >= 1 else { return nil }
        // Wire layout of an error short report:
        //   [0x10][devIdx][0x8F][origSubID][origAddr][errCode][...]
        // After our struct splits subID/address out, address=origSubID and
        // parameters[0]=origAddr, parameters[1]=errCode.
        return (originalSubID: address,
                originalAddress: parameters[0],
                code: parameters.count >= 2 ? parameters[1] : 0)
    }

    public var description: String {
        let hex = parameters.map { String(format: "%02X", $0) }.joined(separator: " ")
        return "HIDPP(\(kind), dev=\(String(format: "0x%02X", deviceIndex)), " +
               "sub=\(String(format: "0x%02X", subID)), " +
               "addr=\(String(format: "0x%02X", address)), [\(hex)])"
    }
}
