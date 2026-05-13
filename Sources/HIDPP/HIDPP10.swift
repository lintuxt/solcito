import Foundation

/// HID++ 1.0 protocol constants. Mostly used by Unifying-era receivers; Bolt
/// uses a different feature-based scheme that lives elsewhere.
///
/// References transliterated from Solaar's
/// `lib/logitech_receiver/hidpp10_constants.py`.
public enum HIDPP10 {

    /// Sub-ID byte values placed at offset 2 of a HID++ report.
    public enum SubID: UInt8, Sendable {
        case setRegisterShort = 0x80
        case getRegisterShort = 0x81
        case setRegisterLong  = 0x82
        case getRegisterLong  = 0x83
        case errorMessage     = 0x8F
    }

    /// HID++ 1.0 receiver registers placed at the "address" byte.
    public enum Register: UInt8, Sendable {
        case notifications       = 0x00
        case connectionState     = 0x02
        /// "Receiver pairing" — multi-purpose, action byte selects behavior:
        ///   0x01 → close pairing lock (cancel)
        ///   0x02 → open pairing lock (enter pairing mode)
        ///   0x03 → unpair device at slot N (slot byte follows)
        case receiverPairing     = 0xB2
        case pairingInfo         = 0xB5  // long-register, sub-addressed
        case firmwareInfo        = 0xF1
    }

    /// Sub-addresses placed in `parameters[0]` of a long-register read of
    /// `Register.pairingInfo` (0xB5). Each returns a different chunk of
    /// metadata about either the receiver itself or one of its paired slots.
    public enum PairingInfoSub {
        public static let serialNumber: UInt8                = 0x01
        public static let firmwareVersion: UInt8             = 0x02
        public static let receiverInformation: UInt8         = 0x03
        public static let pairingInformation: UInt8          = 0x20   // base; add (slot-1)
        public static let extendedPairingInformation: UInt8  = 0x30
        public static let deviceName: UInt8                  = 0x40
        public static let boltPairingInformation: UInt8      = 0x50
        public static let boltDeviceName: UInt8              = 0x60
    }

    /// Unsolicited notification sub-IDs the receiver sends to the host.
    public enum Notification: UInt8, Sendable {
        case deviceDisconnection      = 0x40
        case deviceConnection         = 0x41
        case pairingLockChanged       = 0x4A
        case boltPairing              = 0x4B
    }

    /// Decoded error codes from a 0x8F response.
    public enum ErrorCode: UInt8, Sendable {
        case success              = 0x00
        case invalidSubID         = 0x01
        case invalidAddress       = 0x02
        case invalidValue         = 0x03
        case connectFail          = 0x04
        case tooManyDevices       = 0x05
        case alreadyExists        = 0x06
        case busy                 = 0x07
        case unknownDevice        = 0x08
        case resourceError        = 0x09
        case requestUnavailable   = 0x0A
        case unsupportedParam     = 0x0B
        case wrongPinCode         = 0x0C
        case unknown              = 0xFF
    }
}
