import Foundation
import IOKit

public enum HIDError: Error, CustomStringConvertible {
    case managerCreateFailed
    case managerOpenFailed(IOReturn)
    case deviceOpenFailed(IOReturn)
    case sendReportFailed(IOReturn)
    case getReportFailed(IOReturn)
    case propertyMissing(String)

    public var description: String {
        switch self {
        case .managerCreateFailed:
            return "Failed to create IOHIDManager"
        case .managerOpenFailed(let r):
            return "IOHIDManagerOpen failed (IOReturn=0x\(String(r, radix: 16)))"
        case .deviceOpenFailed(let r):
            return "IOHIDDeviceOpen failed (IOReturn=0x\(String(r, radix: 16)))"
        case .sendReportFailed(let r):
            return "IOHIDDeviceSetReport failed (IOReturn=0x\(String(r, radix: 16)))"
        case .getReportFailed(let r):
            return "IOHIDDeviceGetReport failed (IOReturn=0x\(String(r, radix: 16)))"
        case .propertyMissing(let key):
            return "Missing required HID property: \(key)"
        }
    }
}
