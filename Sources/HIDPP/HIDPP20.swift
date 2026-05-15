import Foundation

/// HID++ 2.0 protocol constants. Feature-based access: every device exposes
/// a set of features identified by 16-bit IDs. The Root feature (0x0000) is
/// always at index 0 and maps feature IDs to per-device indexes.
public enum HIDPP20 {

    /// Standard feature IDs we care about for receiver-info readout.
    /// Solaar's `hidpp20_constants.py` enumerates the full catalog (100+);
    /// we only model what the pairing/info slices actually call.
    public enum FeatureID: UInt16, Sendable, CaseIterable {
        case root              = 0x0000
        case featureSet        = 0x0001
        case deviceInformation = 0x0003
        case deviceName        = 0x0005
        /// Older battery feature, percent + status. Pre-2018ish devices.
        case batteryStatus     = 0x1000
        /// Battery in millivolts. We convert to percent via a Li-Ion
        /// charge curve. Often reports a real number when the discrete
        /// "level" features fall back to "unknown" while charging.
        case batteryVoltage    = 0x1001
        /// Modern battery feature, percent + status + charge flags.
        /// Most current Logitech devices expose this.
        case unifiedBattery    = 0x1004
    }

    /// HID++ 2.0 error codes. Returned in the response body when an error
    /// report (marker subID=0xFF) is received.
    public enum ErrorCode: UInt8, Sendable {
        case noError              = 0x00
        case unknown              = 0x01
        case invalidArgument      = 0x02
        case outOfRange           = 0x03
        case hardwareError        = 0x04
        case logitechInternal     = 0x05
        case invalidFeatureIndex  = 0x06
        case invalidFunctionId    = 0x07
        case busy                 = 0x08
        case unsupported          = 0x09
    }

    /// HID++ 2.0 wire format embeds (function, software ID) into the
    /// "address" byte of the HIDPPReport. The high nibble is the function
    /// number; the low nibble is a host-chosen software ID we use to
    /// correlate request/response. We reserve software ID 1 for solcito.
    public static let softwareID: UInt8 = 0x01

    public static func makeAddress(function: UInt8, softwareID: UInt8 = HIDPP20.softwareID) -> UInt8 {
        ((function & 0x0F) << 4) | (softwareID & 0x0F)
    }
}
