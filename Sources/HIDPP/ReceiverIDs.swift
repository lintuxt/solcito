import Foundation

/// A known Logitech-compatible USB receiver, identified by USB VID+PID.
///
/// PID table transliterated from Solaar's `lib/logitech_receiver/base_usb.py`
/// (https://github.com/pwr-Solaar/Solaar). Solaar is GPLv2 — see LICENSE.
public struct ReceiverID: Sendable, Hashable {
    public let vendorID: Int
    public let productID: Int
    public let kind: ReceiverKind
    public let name: String

    public init(vendorID: Int = 0x046D, productID: Int, kind: ReceiverKind, name: String) {
        self.vendorID = vendorID
        self.productID = productID
        self.kind = kind
        self.name = name
    }
}

public enum KnownReceivers {
    public static let logitechVendorID: Int = 0x046D
    public static let lenovoVendorID: Int = 0x17EF

    public static let all: [ReceiverID] = [
        // Bolt
        .init(productID: 0xC548, kind: .bolt, name: "Bolt Receiver"),

        // Unifying
        .init(productID: 0xC52B, kind: .unifying, name: "Unifying Receiver"),
        .init(productID: 0xC532, kind: .unifying, name: "Unifying Receiver"),

        // Nano (Logitech VID)
        .init(productID: 0xC518, kind: .nano, name: "Nano Receiver"),
        .init(productID: 0xC51A, kind: .nano, name: "Nano Receiver"),
        .init(productID: 0xC51B, kind: .nano, name: "Nano Receiver"),
        .init(productID: 0xC521, kind: .nano, name: "Nano Receiver"),
        .init(productID: 0xC525, kind: .nano, name: "Nano Receiver"),
        .init(productID: 0xC526, kind: .nano, name: "Nano Receiver"),
        .init(productID: 0xC52E, kind: .nano, name: "Nano Receiver"),
        .init(productID: 0xC52F, kind: .nano, name: "Nano Receiver Advanced"),
        .init(productID: 0xC531, kind: .nano, name: "Nano Receiver"),
        .init(productID: 0xC534, kind: .nano, name: "Nano Receiver (max 2 devices)"),
        .init(productID: 0xC535, kind: .nano, name: "Nano Receiver (Dell)"),
        .init(productID: 0xC537, kind: .nano, name: "Nano Receiver"),

        // Nano (Lenovo-branded, different VID)
        .init(vendorID: lenovoVendorID, productID: 0x6042, kind: .nano, name: "Lenovo Nano Receiver"),

        // Lightspeed
        .init(productID: 0xC539, kind: .lightspeed, name: "Lightspeed Receiver"),
        .init(productID: 0xC53A, kind: .lightspeed, name: "Lightspeed Receiver"),
        .init(productID: 0xC53D, kind: .lightspeed, name: "Lightspeed Receiver"),
        .init(productID: 0xC53F, kind: .lightspeed, name: "Lightspeed Receiver"),
        .init(productID: 0xC541, kind: .lightspeed, name: "Lightspeed Receiver"),
        .init(productID: 0xC545, kind: .lightspeed, name: "Lightspeed Receiver"),
        .init(productID: 0xC547, kind: .lightspeed, name: "Lightspeed Receiver"),
        .init(productID: 0xC54D, kind: .lightspeed, name: "Lightspeed Receiver"),

        // 27 MHz
        .init(productID: 0xC517, kind: .ex100_27mhz, name: "EX100 Receiver 27 MHz"),
    ]

    public static func lookup(vendorID: Int, productID: Int) -> ReceiverID? {
        all.first { $0.vendorID == vendorID && $0.productID == productID }
    }

    public static var allVendorIDs: Set<Int> {
        Set(all.map(\.vendorID))
    }
}
