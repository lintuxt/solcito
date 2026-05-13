import Foundation
import IOKit
import IOKit.hid

/// Owns an `IOHIDManager` for the lifetime of the app. Discovery returns
/// `HIDDeviceHandle`s whose underlying `IOHIDDevice` references remain valid
/// for as long as this manager is retained.
public final class HIDManager: @unchecked Sendable {

    private let manager: IOHIDManager
    private var isOpen = false

    public init() {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit {
        if isOpen {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    /// Returns every HID interface whose USB vendor ID is in `vendorIDs`.
    /// One physical receiver typically shows up as multiple handles (mouse
    /// interface, keyboard interface, HID++ vendor interface) — callers group
    /// by `locationID` to recover the physical device.
    public func discover(vendorIDs: [Int]) throws -> [HIDDeviceHandle] {
        let matching = vendorIDs.map { vid -> [String: Any] in
            [kIOHIDVendorIDKey: vid]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        if !isOpen {
            let r = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard r == kIOReturnSuccess else { throw HIDError.managerOpenFailed(r) }
            isOpen = true
        }

        guard let nsSet = IOHIDManagerCopyDevices(manager) as NSSet? else { return [] }
        return nsSet.compactMap { HIDDeviceHandle(device: $0 as! IOHIDDevice, owner: self) }
    }
}

/// A discovered HID interface. Wraps the raw `IOHIDDevice` plus the static
/// metadata we extracted at discovery time. Retains its parent `HIDManager`
/// so the underlying `IOHIDDevice` stays valid until the handle (and any
/// `HIDDevice` opened from it) is released.
public struct HIDDeviceHandle: @unchecked Sendable {
    public let info: HIDDeviceInfo
    internal let device: IOHIDDevice
    internal let owner: HIDManager

    init?(device: IOHIDDevice, owner: HIDManager) {
        guard let info = HIDDeviceHandle.info(for: device) else { return nil }
        self.device = device
        self.info = info
        self.owner = owner
    }

    private static func info(for device: IOHIDDevice) -> HIDDeviceInfo? {
        guard let vid: Int = prop(device, kIOHIDVendorIDKey),
              let pid: Int = prop(device, kIOHIDProductIDKey) else {
            return nil
        }
        return HIDDeviceInfo(
            vendorID: vid,
            productID: pid,
            primaryUsagePage: prop(device, kIOHIDPrimaryUsagePageKey) ?? 0,
            primaryUsage: prop(device, kIOHIDPrimaryUsageKey) ?? 0,
            locationID: UInt64(prop(device, kIOHIDLocationIDKey) ?? 0),
            product: prop(device, kIOHIDProductKey),
            manufacturer: prop(device, kIOHIDManufacturerKey),
            serialNumber: prop(device, kIOHIDSerialNumberKey),
            transport: prop(device, kIOHIDTransportKey)
        )
    }

    private static func prop<T>(_ device: IOHIDDevice, _ key: String) -> T? {
        IOHIDDeviceGetProperty(device, key as CFString) as? T
    }
}
