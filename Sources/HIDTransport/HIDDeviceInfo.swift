import Foundation

/// Static information about a HID interface discovered via IOKit. Logitech
/// receivers expose multiple HID interfaces per physical receiver; consumers
/// typically dedupe by `locationID` and then pick the interface that carries
/// HID++ traffic (long-report capable).
public struct HIDDeviceInfo: Sendable, Hashable {
    public let vendorID: Int
    public let productID: Int
    public let primaryUsagePage: Int
    public let primaryUsage: Int
    public let locationID: UInt64
    public let product: String?
    public let manufacturer: String?
    public let serialNumber: String?
    public let transport: String?

    public init(
        vendorID: Int,
        productID: Int,
        primaryUsagePage: Int,
        primaryUsage: Int,
        locationID: UInt64,
        product: String?,
        manufacturer: String?,
        serialNumber: String?,
        transport: String?
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.primaryUsagePage = primaryUsagePage
        self.primaryUsage = primaryUsage
        self.locationID = locationID
        self.product = product
        self.manufacturer = manufacturer
        self.serialNumber = serialNumber
        self.transport = transport
    }
}
