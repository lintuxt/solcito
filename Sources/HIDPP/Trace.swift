import Foundation

/// Lightweight HID++ protocol-layer tracer. Enabled by setting the
/// `SOLCITO_HIDPP_TRACE` environment variable to any non-empty value.
/// Companion to the wire-level `SOLCITO_HID_TRACE` in HIDTransport.
///
/// All output goes to stderr so it doesn't pollute stdout for callers that
/// pipe / parse normal output.
enum HIDPPTrace {

    private static let enabled: Bool = {
        let v = ProcessInfo.processInfo.environment["SOLCITO_HIDPP_TRACE"]
        return v != nil && !(v ?? "").isEmpty
    }()

    private static let startedAt = Date()

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        let line = String(format: "[hidpp %8.3fs] %@\n", elapsed, message())
        FileHandle.standardError.write(Data(line.utf8))
    }

    static func hex(_ byte: UInt8) -> String { String(format: "0x%02X", byte) }
    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Human-readable label for a HID++ 1.0 sub-ID when we recognise it.
    static func subIDLabel(_ b: UInt8) -> String {
        switch b {
        case 0x80: return "SET_REG_SHORT"
        case 0x81: return "GET_REG_SHORT"
        case 0x82: return "SET_REG_LONG"
        case 0x83: return "GET_REG_LONG"
        case 0x8F: return "ERROR_1.0"
        case 0xFF: return "ERROR_2.0"
        case 0x40: return "DISCONNECT_NOTIF"
        case 0x41: return "CONNECT_NOTIF"
        case 0x4A: return "LOCK_NOTIF"
        default:   return "sub=\(hex(b))"
        }
    }
}
