import Foundation

/// Semantic events emitted during a pairing window, decoded from raw
/// HID++ 1.0 notifications. `raw` is the escape hatch for reports we don't
/// have a typed case for yet (Bolt-specific, DJ-layer, etc.).
public enum PairingEvent: Sendable {
    case lockOpened
    case lockClosed(success: Bool, errorCode: UInt8?)
    case deviceConnected(slot: Int, wpid: UInt16?, deviceKind: PairedDeviceKind?)
    case deviceDisconnected(slot: Int)
    case raw(HIDPPReport)

    public static func decode(_ report: HIDPPReport) -> PairingEvent {
        // Pairing-lock state change (HID++ 1.0). Solaar's handler
        // (lib/logitech_receiver/notifications.py, handle_pairing_lock):
        //   lock_open  = bool(address & 0x01)
        //   pair_error = data[0]   (0 = no error)
        // So the address byte's bit 0 carries the new lock state, and
        // params[0] carries an error code if pairing failed.
        if report.subID == HIDPP10.Notification.pairingLockChanged.rawValue {
            let lockIsOpen = (report.address & 0x01) != 0
            let pairError = report.parameters.first ?? 0
            if lockIsOpen {
                return .lockOpened
            }
            return .lockClosed(success: pairError == 0,
                               errorCode: pairError == 0 ? nil : pairError)
        }

        // Device connect/disconnect notifications: deviceIndex is the slot
        // number (1..6 for Unifying). Long-form connection notifications
        // carry the WPID and device-kind nibble.
        if report.subID == HIDPP10.Notification.deviceConnection.rawValue,
           report.deviceIndex != 0xFF {
            let slot = Int(report.deviceIndex)
            let kind = PairedDeviceKind(rawNibble: report.parameters.first.map { Int($0 & 0x0F) })
            let wpid: UInt16? = {
                guard report.parameters.count >= 3 else { return nil }
                return (UInt16(report.parameters[1]) << 8) | UInt16(report.parameters[2])
            }()
            return .deviceConnected(slot: slot, wpid: wpid, deviceKind: kind)
        }
        if report.subID == HIDPP10.Notification.deviceDisconnection.rawValue,
           report.deviceIndex != 0xFF {
            return .deviceDisconnected(slot: Int(report.deviceIndex))
        }

        return .raw(report)
    }
}

/// Coarse device-kind classification carried in the low nibble of HID++ 1.0
/// connection notifications. Matches Solaar's `DeviceKind` enum.
public enum PairedDeviceKind: Int, Sendable, CaseIterable, CustomStringConvertible {
    case keyboard       = 1
    case mouse          = 2
    case numpad         = 3
    case presenter      = 4
    case remoteControl  = 7
    case trackball      = 8
    case touchpad       = 9

    public init?(rawNibble: Int?) {
        guard let n = rawNibble, let value = PairedDeviceKind(rawValue: n) else { return nil }
        self = value
    }

    public var description: String {
        switch self {
        case .keyboard:      return "Keyboard"
        case .mouse:         return "Mouse"
        case .numpad:        return "Numpad"
        case .presenter:     return "Presenter"
        case .remoteControl: return "Remote"
        case .trackball:     return "Trackball"
        case .touchpad:      return "Touchpad"
        }
    }
}
