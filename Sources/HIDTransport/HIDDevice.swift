import Foundation
import IOKit
import IOKit.hid

/// A single open HID interface. Read input reports off `inputReports`, write
/// output reports via `send(reportID:_:)`.
public final class HIDDevice: @unchecked Sendable {

    public let info: HIDDeviceInfo
    private let device: IOHIDDevice
    private let owner: HIDManager  // retains the IOHIDManager that vended `device`
    private let queue: DispatchQueue
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private let bufferSize: Int
    private var opened = false

    private let continuation: AsyncStream<HIDReport>.Continuation
    public let inputReports: AsyncStream<HIDReport>

    public init(handle: HIDDeviceHandle, inputBufferSize: Int = 64) {
        self.info = handle.info
        self.device = handle.device
        self.owner = handle.owner
        self.bufferSize = inputBufferSize
        self.queue = DispatchQueue(label: "solcito.hid.\(String(format: "%08X", handle.info.locationID))")
        var c: AsyncStream<HIDReport>.Continuation!
        self.inputReports = AsyncStream(bufferingPolicy: .bufferingNewest(64)) { c = $0 }
        self.continuation = c
    }

    deinit {
        close()
    }

    public func open() throws {
        guard !opened else { return }
        let r = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw HIDError.deviceOpenFailed(r) }

        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        self.inputBuffer = buf

        // Retain self via the context pointer so a late-arriving callback
        // never dereferences freed memory. Released in close() once the
        // dispatch queue has been cancelled.
        let context = Unmanaged.passRetained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            buf,
            bufferSize,
            { (ctx, _, _, _, reportID, reportPtr, reportLength) in
                guard let ctx else { return }
                let me = Unmanaged<HIDDevice>.fromOpaque(ctx).takeUnretainedValue()
                // macOS quirk: for numbered reports the input buffer's byte[0]
                // is the report ID itself, NOT report body. Strip it so
                // `payload` matches our outgoing-send convention.
                let raw = UnsafeBufferPointer(start: reportPtr, count: reportLength)
                let body: Data
                if reportID != 0, reportLength > 0, raw[0] == UInt8(reportID) {
                    body = Data(buffer: UnsafeBufferPointer(start: raw.baseAddress! + 1, count: reportLength - 1))
                } else {
                    body = Data(buffer: raw)
                }
                if ProcessInfo.processInfo.environment["SOLCITO_HID_TRACE"] != nil {
                    let full = Data(buffer: raw)
                    let hex = full.map { String(format: "%02X", $0) }.joined(separator: " ")
                    FileHandle.standardError.write(Data("hid<-  id=\(String(format: "%02X", reportID)) len=\(reportLength) [\(hex)]\n".utf8))
                }
                me.continuation.yield(HIDReport(reportID: UInt8(reportID), payload: body))
            },
            context
        )
        // Set the cancel handler before scheduling so we know when the
        // dispatch queue has finished draining and can safely free the
        // retained `self` context + input buffer.
        IOHIDDeviceSetCancelHandler(device) { [weak self] in
            guard let self else { return }
            self.continuation.finish()
            if let p = self.inputBuffer { p.deallocate(); self.inputBuffer = nil }
            Unmanaged<HIDDevice>.fromOpaque(context).release()
        }
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceActivate(device)
        opened = true
    }

    public func close() {
        guard opened else { return }
        opened = false
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceCancel(device)  // triggers the cancel handler (above)
    }

    /// Send an output report. `payload` is the report body (not including the
    /// report ID byte). For HID++ short reports, payload is 6 bytes; for long
    /// reports, 19 bytes.
    ///
    /// macOS quirk (matches hidapi): for *numbered* HID reports, the buffer
    /// passed to `IOHIDDeviceSetReport` must include the report ID byte as
    /// `buf[0]` AND the `reportID` parameter must equal that same byte. If we
    /// pass just the payload, the call fails with IOReturn=0xE0005000.
    public func send(reportID: UInt8, _ payload: Data) throws {
        var framed = Data(capacity: payload.count + 1)
        framed.append(reportID)
        framed.append(payload)

        let r = framed.withUnsafeBytes { raw -> IOReturn in
            guard let base = raw.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(reportID),
                base.assumingMemoryBound(to: UInt8.self),
                framed.count
            )
        }
        guard r == kIOReturnSuccess else { throw HIDError.sendReportFailed(r) }
        if ProcessInfo.processInfo.environment["SOLCITO_HID_TRACE"] != nil {
            let hex = framed.map { String(format: "%02X", $0) }.joined(separator: " ")
            FileHandle.standardError.write(Data("hid->  id=\(String(format: "%02X", reportID)) len=\(framed.count) [\(hex)]\n".utf8))
        }
    }
}

/// A raw HID input report: report ID byte plus the payload bytes that
/// followed it. Note the payload does NOT include the report ID itself.
public struct HIDReport: Sendable, Hashable {
    public let reportID: UInt8
    public let payload: Data

    public init(reportID: UInt8, payload: Data) {
        self.reportID = reportID
        self.payload = payload
    }
}
