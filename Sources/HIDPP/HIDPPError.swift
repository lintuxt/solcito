import Foundation

public enum HIDPPError: Error, CustomStringConvertible {
    case timeout
    case noHIDPPInterface
    case protocolError(originalSubID: UInt8, register: UInt8, code: UInt8)
    case unexpectedResponse(HIDPPReport)

    public var description: String {
        switch self {
        case .timeout:
            return "HID++ request timed out"
        case .noHIDPPInterface:
            return "Receiver does not expose a HID++ (usagePage=0xFF00) interface"
        case .protocolError(let sub, let reg, let code):
            let codeName = HIDPP10.ErrorCode(rawValue: code).map { "\($0)" } ?? "0x\(String(format: "%02X", code))"
            return "HID++ error (subID=0x\(String(format: "%02X", sub)) " +
                   "reg=0x\(String(format: "%02X", reg))): \(codeName)"
        case .unexpectedResponse(let r):
            return "Unexpected HID++ response: \(r)"
        }
    }
}
