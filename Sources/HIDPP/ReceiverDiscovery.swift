import Foundation
import HIDTransport

/// Groups raw HID interfaces into physical receivers. Each Logitech receiver
/// exposes several interfaces (mouse, keyboard, HID++ vendor); we want to
/// surface one receiver entry plus a handle on the HID++ interface
/// (`primaryUsagePage == 0xFF00`).
public struct DiscoveredReceiver: Sendable {
    public let id: ReceiverID
    public let interfaces: [HIDDeviceHandle]

    public var locationID: UInt64 { interfaces.first?.info.locationID ?? 0 }

    /// The vendor-defined HID++ interface — the one we send register reads
    /// over. Nil if the receiver doesn't expose one (very old hardware).
    public var hidppInterface: HIDDeviceHandle? {
        interfaces.first { $0.info.primaryUsagePage == 0xFF00 }
    }
}

public enum ReceiverDiscovery {

    /// Group discovered HID handles into known receivers, by `locationID`.
    public static func find(using manager: HIDManager) throws -> [DiscoveredReceiver] {
        let vendorIDs = Array(KnownReceivers.allVendorIDs)
        let handles = try manager.discover(vendorIDs: vendorIDs)

        var grouped: [UInt64: (ReceiverID, [HIDDeviceHandle])] = [:]
        for h in handles {
            guard let id = KnownReceivers.lookup(vendorID: h.info.vendorID, productID: h.info.productID) else {
                continue
            }
            grouped[h.info.locationID, default: (id, [])].1.append(h)
            if grouped[h.info.locationID]?.0 == nil {
                grouped[h.info.locationID] = (id, grouped[h.info.locationID]?.1 ?? [h])
            }
        }
        return grouped
            .map { (_, value) in DiscoveredReceiver(id: value.0, interfaces: value.1) }
            .sorted { $0.locationID < $1.locationID }
    }
}
