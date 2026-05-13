import Foundation
import HIDPP

/// Human-readable rendering of a `PairingEvent` for log views.
func formatPairingEvent(_ event: PairingEvent) -> String {
    switch event {
    case .lockOpened:
        return "Lock opened — receiver discoverable."
    case .lockClosed(let success, let code):
        if success { return "Lock closed." }
        return "Lock closed with error code 0x\(String(format: "%02X", code ?? 0))."
    case .deviceConnected(let slot, let wpid, let kind):
        let wpidStr = wpid.map { String(format: "0x%04X", $0) } ?? "—"
        let kindStr = kind?.description ?? "Device"
        return "Slot \(slot): \(kindStr) connected (WPID \(wpidStr))."
    case .deviceDisconnected(let slot):
        return "Slot \(slot) disconnected."
    case .raw(let r):
        let hex = r.parameters.prefix(6).map { String(format: "%02X", $0) }.joined(separator: " ")
        return "[raw] dev=\(String(format: "0x%02X", r.deviceIndex)) sub=\(String(format: "0x%02X", r.subID)) [\(hex)]"
    }
}
