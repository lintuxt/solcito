import Foundation

/// Everything we know about a paired device in a single slot. All fields
/// are optional because solcito reads them best-effort over HID++ — some
/// firmware variants reject the underlying register reads, and the
/// decoder degrades gracefully when bytes are missing.
public struct DeviceDetails: Sendable, Hashable {
    public let slot: Int
    public let name: String?              // receiver-stored marketing name ("MX Ergo")
    public let kind: PairedDeviceKind?    // mouse / keyboard / trackball / …
    public let wpid: UInt16?              // Logitech wireless product ID
    public let battery: BatteryReading?   // last-seen battery status, if device was awake

    public init(slot: Int,
                name: String? = nil,
                kind: PairedDeviceKind? = nil,
                wpid: UInt16? = nil,
                battery: BatteryReading? = nil) {
        self.slot = slot
        self.name = name
        self.kind = kind
        self.wpid = wpid
        self.battery = battery
    }

    // MARK: - Wire-format parsers

    /// Parse a HID++ 1.0 long-register response for `0xB5` sub-address
    /// `0x40 + (slot - 1)` (Unifying-style device-name read). Returns nil
    /// when bytes don't match the expected layout.
    public static func parseDeviceName(parameters: [UInt8], expectedSub: UInt8) -> String? {
        guard parameters.count >= 2, parameters[0] == expectedSub else { return nil }
        let length = Int(parameters[1])
        guard length > 0, parameters.count >= 2 + length else { return nil }
        let bytes = Array(parameters[2..<(2 + length)])
        guard let str = String(bytes: bytes, encoding: .ascii) else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Parse a HID++ 1.0 long-register response for `0xB5` sub-address
    /// `0x20 + (slot - 1)` (Unifying-style pairing-info read).
    public static func parsePairingInfo(parameters: [UInt8], expectedSub: UInt8) -> (kind: PairedDeviceKind?, wpid: UInt16?)? {
        guard parameters.count >= 8, parameters[0] == expectedSub else { return nil }
        let wpid = (UInt16(parameters[3]) << 8) | UInt16(parameters[4])
        let kindNibble = Int(parameters[7] & 0x0F)
        let kind = PairedDeviceKind(rawValue: kindNibble)
        return (kind, wpid == 0 ? nil : wpid)
    }

    /// Parse a HID++ 2.0 feature `0x1004` UnifiedBattery `GetStatus`
    /// response. Layout:
    ///   parameters[0] = state of charge (percent, 0–100)
    ///   parameters[2] = status enum (0 discharging, 1+ charging variants)
    public static func parseUnifiedBattery(parameters: [UInt8]) -> BatteryReading? {
        guard parameters.count >= 3 else { return nil }
        let percent = Int(parameters[0])
        guard (0...100).contains(percent) else { return nil }
        let status = parameters[2]
        let charging = (status != 0)
        return BatteryReading(percent: percent, isCharging: charging)
    }

    /// Parse a HID++ 2.0 feature `0x1000` BatteryStatus `GetLevelStatus`
    /// response. Layout:
    ///   parameters[0] = discharge level (percent, 0–100)
    ///   parameters[2] = status: 0 discharging, 1 recharging,
    ///                           2 charge complete, 3 charge failure
    public static func parseLegacyBattery(parameters: [UInt8]) -> BatteryReading? {
        guard parameters.count >= 3 else { return nil }
        let percent = Int(parameters[0])
        guard (0...100).contains(percent) else { return nil }
        let status = parameters[2]
        let charging = (status == 1 || status == 2)
        return BatteryReading(percent: percent, isCharging: charging)
    }
}

/// One battery measurement read from a paired device.
public struct BatteryReading: Sendable, Hashable {
    public let percent: Int
    public let isCharging: Bool

    public init(percent: Int, isCharging: Bool) {
        self.percent = percent
        self.isCharging = isCharging
    }
}

/// Small WPID → marketing-name lookup, used only when the receiver-stored
/// name read fails. Sourced from Solaar's
/// `lib/logitech_receiver/descriptors.py`. The receiver-stored name is
/// always preferred when available — this table is a last-resort fallback.
public enum WPIDLookup {
    public static let knownModels: [UInt16: String] = [
        // Keyboards
        0x4002: "K750 Solar Keyboard",
        0x4023: "MK270 Keyboard",
        0x4061: "K375s Keyboard",
        0x4066: "Craft Keyboard",
        0x406E: "K800 Illuminated Keyboard",
        0x4075: "K470 Keyboard",
        0x405B: "K780 Keyboard",
        0x408A: "MX Keys Keyboard",
        // Mice
        0x4017: "M345 Mouse",
        0x4051: "M510 Mouse",
        0x4055: "M185/M235/M310 Mouse",
        0x4041: "MX Master",
        0x404A: "Anywhere MX 2",
        0x4069: "MX Master 2S",
        0x406B: "M585/M590 Silent Mouse",
        0x407B: "MX Vertical Mouse",
        0x4080: "Pebble M350 Mouse",
        0x4082: "MX Master 3 Mouse",
    ]

    public static func name(for wpid: UInt16) -> String? {
        knownModels[wpid]
    }
}

/// Renders a `DeviceDetails` as a short user-facing label. Falls back
/// progressively as fewer fields are known. If the resolved name already
/// contains the kind (e.g. "MX Ergo Multi-Device Trackball" + .trackball),
/// the parenthetical is dropped to avoid awkward duplication.
public func formatDeviceLabel(_ d: DeviceDetails) -> String {
    let name: String? = d.name ?? d.wpid.flatMap(WPIDLookup.name(for:))
    let kindStr = d.kind?.description
    switch (name, kindStr) {
    case let (n?, k?):
        if n.localizedCaseInsensitiveContains(k) { return n }
        return "\(n) (\(k))"
    case let (n?, nil): return n
    case let (nil, k?): return k
    default:            return "paired"
    }
}
