import Foundation

/// Logitech receiver families. Pairing behavior differs across families, so we
/// classify receivers by kind and pick the appropriate flow.
public enum ReceiverKind: String, Sendable, CaseIterable {
    case unifying
    case bolt
    case lightspeed
    case nano
    case ex100_27mhz
    case unknown

    public var displayName: String {
        switch self {
        case .unifying:    return "Unifying"
        case .bolt:        return "Bolt"
        case .lightspeed:  return "Lightspeed"
        case .nano:        return "Nano"
        case .ex100_27mhz: return "EX100 (27 MHz)"
        case .unknown:     return "Unknown"
        }
    }

    /// Whether this kind supports adding/removing paired devices over HID++.
    /// Nano and EX100 are typically pre-paired and not re-pairable at runtime.
    public var supportsPairing: Bool {
        switch self {
        case .unifying, .bolt, .lightspeed: return true
        case .nano, .ex100_27mhz, .unknown: return false
        }
    }
}
