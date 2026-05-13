import Testing
@testable import HIDTransport

@Suite("HIDDeviceInfo")
struct HIDDeviceInfoTests {

    @Test("Value semantics + equality")
    func equality() {
        let a = HIDDeviceInfo(
            vendorID: 0x046D, productID: 0xC52B,
            primaryUsagePage: 0xFF00, primaryUsage: 0x0001,
            locationID: 0x14200000,
            product: "USB Receiver", manufacturer: "Logitech",
            serialNumber: nil, transport: "USB"
        )
        let b = a
        #expect(a == b)
    }
}
