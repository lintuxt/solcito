import Foundation
import HIDTransport

/// High-level handle for a Logitech receiver. Wraps the HID++ interface and
/// exposes typed operations (read receiver info, list paired devices, …).
public final class Receiver: @unchecked Sendable {

    public let id: ReceiverID
    public let interface: HIDDeviceInfo
    private let device: HIDDevice

    public init(id: ReceiverID, hidppDevice: HIDDevice) {
        self.id = id
        self.interface = hidppDevice.info
        self.device = hidppDevice
    }

    public func open() throws { try device.open() }
    public func close()       { device.close() }

    /// Raw inbound HID++ reports — notifications, async responses, anything
    /// the receiver volunteers. Callers should consume this AFTER any pending
    /// `request()` calls have completed (single-iterator model).
    public var notifications: AsyncStream<HIDPPReport> {
        AsyncStream { continuation in
            let task = Task {
                for await raw in self.device.inputReports {
                    if let parsed = HIDPPReport.parse(reportID: raw.reportID, payload: raw.payload) {
                        continuation.yield(parsed)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Decoded pairing-window events. Wraps `notifications` and filters/maps
    /// each report through `PairingEvent.decode`.
    public var pairingEvents: AsyncStream<PairingEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await report in self.notifications {
                    continuation.yield(PairingEvent.decode(report))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Pairing

    /// Put the receiver into "open lock" (discoverable) state. Devices that
    /// have their pair button pressed within `timeoutSeconds` will be
    /// assigned to an open slot. `slot == 0` lets the receiver pick any
    /// available slot; pass 1...maxSlots to force a specific one.
    public func beginPairing(timeoutSeconds: UInt8 = 30, slot: UInt8 = 0) async throws {
        _ = try await request(
            kind: .short,
            subID: .setRegisterShort,
            register: .deviceConnect,
            parameters: [0x02, slot, timeoutSeconds]
        )
    }

    /// Cancel an in-progress pairing window early.
    public func cancelPairing() async throws {
        _ = try await request(
            kind: .short,
            subID: .setRegisterShort,
            register: .deviceConnect,
            parameters: [0x01, 0x00, 0x00]
        )
    }

    /// Unpair the device at the given slot (1...maxSlots).
    public func unpair(slot: UInt8) async throws {
        _ = try await request(
            kind: .short,
            subID: .setRegisterShort,
            register: .deviceDisconnect,
            parameters: [slot, 0x00, 0x00]
        )
    }

    // MARK: - Paired-device discovery

    /// Ping each slot 1..`maxSlots` and return summary info for the ones that
    /// answer. Uses HID++ 2.0 Root.GetProtocolVersion (feature index 0,
    /// function 1) — works regardless of whether the receiver itself speaks
    /// HID++ 2.0, because the paired devices answer for themselves.
    public func pairedDevices(maxSlots: Int = 6, perSlotTimeout: Duration = .milliseconds(400)) async -> [PairedDeviceSummary] {
        var results: [PairedDeviceSummary] = []
        for slot in 1...UInt8(maxSlots) {
            if let summary = await pingSlot(slot, timeout: perSlotTimeout) {
                results.append(summary)
            }
        }
        return results
    }

    private func pingSlot(_ slot: UInt8, timeout: Duration) async -> PairedDeviceSummary? {
        // Root.GetProtocolVersion: feature index 0, function 1. Send a
        // distinctive byte as parameters[2] (the "ping data"); the device
        // echoes it back in the response, which proves it's the right
        // responder rather than stale traffic.
        let pingByte: UInt8 = 0x5A
        guard let resp = try? await featureRequest(
            deviceIndex: slot,
            featureIndex: 0,
            function: 1,
            parameters: [0x00, 0x00, pingByte],
            kind: .short,
            timeout: timeout
        ) else { return nil }

        let p = resp.parameters
        // Successful ping echoes pingByte at params[2]; some firmwares place
        // it at params[0] for short-report variants. Accept either.
        let echoed = (p.count >= 3 && p[2] == pingByte) || (p.first == pingByte)
        guard echoed else { return nil }

        let major = p.count >= 1 ? p[0] : 0
        let minor = p.count >= 2 ? p[1] : 0
        return PairedDeviceSummary(slot: Int(slot), hidppMajor: major, hidppMinor: minor)
    }

    // MARK: - HID++ request/response

    /// Low-level: send a fully-formed `HIDPPReport` and await the matching
    /// response. Filters unrelated input (notifications, other registers /
    /// features) and routes both HID++ 1.0 errors (subID=0x8F) and HID++ 2.0
    /// errors (subID=0xFF) back as a thrown `HIDPPError.protocolError`.
    ///
    /// **Concurrency:** must not be called concurrently on the same
    /// `Receiver`. Each call iterates the underlying `device.inputReports`
    /// AsyncStream, and that stream yields every event to a single consumer
    /// — overlapping iterators steal each other's responses and time out.
    /// Callers serialize their own work; a follow-up slice will move this
    /// behind an actor that queues internally.
    public func send(_ outgoing: HIDPPReport, timeout: Duration = .seconds(2)) async throws -> HIDPPReport {
        try device.send(reportID: outgoing.kind.rawValue, outgoing.serializedPayload())
        let expectedSubID = outgoing.subID
        let expectedAddress = outgoing.address

        return try await withThrowingTaskGroup(of: HIDPPReport.self) { group in
            group.addTask {
                for await report in self.device.inputReports {
                    guard let hidpp = HIDPPReport.parse(reportID: report.reportID, payload: report.payload) else { continue }
                    // Error correlation: in both 1.0 and 2.0, the error
                    // report's `address` field carries the *original* subID
                    // (or feature index), and `parameters[0]` carries the
                    // original register / fn|swid.
                    if hidpp.isError,
                       let err = hidpp.errorPayload,
                       err.originalSubID == expectedSubID,
                       err.originalAddress == expectedAddress {
                        throw HIDPPError.protocolError(
                            originalSubID: err.originalSubID,
                            register: err.originalAddress,
                            code: err.code
                        )
                    }
                    if hidpp.subID == expectedSubID && hidpp.address == expectedAddress {
                        return hidpp
                    }
                }
                throw HIDPPError.timeout
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw HIDPPError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    /// HID++ 1.0 typed wrapper: send a register read/write to the receiver.
    public func request(
        kind: HIDPPReportKind,
        subID: HIDPP10.SubID,
        register: HIDPP10.Register,
        parameters: [UInt8] = [],
        timeout: Duration = .seconds(2)
    ) async throws -> HIDPPReport {
        let outgoing = HIDPPReport(
            kind: kind,
            deviceIndex: HIDPPReport.receiverDeviceIndex,
            subID: subID.rawValue,
            address: register.rawValue,
            parameters: parameters
        )
        return try await send(outgoing, timeout: timeout)
    }

    /// HID++ 2.0 typed wrapper: call a function on a feature by its
    /// (per-device) index. Use `featureIndex(for:)` to resolve a `FeatureID`
    /// to its index first. `deviceIndex` defaults to the receiver (0xFF);
    /// pass 1..6 to call a paired device directly through the receiver.
    public func featureRequest(
        deviceIndex: UInt8 = HIDPPReport.receiverDeviceIndex,
        featureIndex: UInt8,
        function: UInt8,
        parameters: [UInt8] = [],
        kind: HIDPPReportKind = .long,
        timeout: Duration = .seconds(2)
    ) async throws -> HIDPPReport {
        let outgoing = HIDPPReport(
            kind: kind,
            deviceIndex: deviceIndex,
            subID: featureIndex,
            address: HIDPP20.makeAddress(function: function),
            parameters: parameters
        )
        return try await send(outgoing, timeout: timeout)
    }

    /// Look up the per-device index assigned to a given HID++ 2.0 feature.
    /// Calls Root.GetFeature (feature 0, function 0). Throws if the device
    /// doesn't expose the feature (response carries index 0x00, which the
    /// spec reserves for "not present").
    public func featureIndex(for feature: HIDPP20.FeatureID) async throws -> UInt8 {
        let fid = feature.rawValue
        let resp = try await featureRequest(
            featureIndex: 0,
            function: 0,
            parameters: [UInt8(fid >> 8), UInt8(fid & 0xFF)]
        )
        let idx = resp.parameters.first ?? 0
        guard idx != 0 || feature == .root else {
            throw HIDPPError.unexpectedResponse(resp)
        }
        return idx
    }

    // MARK: - Typed reads

    public func info() async throws -> ReceiverInfo {
        let connState = try await request(
            kind: .short,
            subID: .getRegisterShort,
            register: .connectionState
        )

        // Try HID++ 1.0 first (register 0xB5). On older Unifying firmware
        // this is the only way; on newer firmware the receiver rejects 0xB5
        // and we have to use HID++ 2.0 features instead.
        let rx1 = try? await request(
            kind: .long, subID: .getRegisterLong,
            register: .pairingInfo,
            parameters: [HIDPP10.PairingInfoSub.receiverInformation]
        )
        let fw1 = try? await request(
            kind: .long, subID: .getRegisterLong,
            register: .pairingInfo,
            parameters: [HIDPP10.PairingInfoSub.firmwareVersion]
        )

        var serial: String? = nil
        var maxDevices: Int? = nil
        var firmware: String? = nil

        if let rx = rx1 {
            (serial, maxDevices) = ReceiverInfo.decodeReceiverInfoRegister(rx)
        }
        if let fw = fw1 {
            firmware = ReceiverInfo.decodeFirmwareRegister(fw)
        }

        // HID++ 1.0 fallback: register 0xF1 (firmware info, short read). Older
        // Unifying firmwares that rejected 0xB5 often still answer here.
        if firmware == nil {
            firmware = await readFirmwareF1()
        }

        // HID++ 2.0 fallback: feature 0x0003 DeviceInformation. Modern
        // receivers (Bolt, newer Unifying revs) expose info this way.
        if serial == nil || firmware == nil {
            if let info2 = try? await readDeviceInformationV2() {
                serial = serial ?? info2.serialNumber
                firmware = firmware ?? info2.firmwareVersion
            }
        }

        return ReceiverInfo(
            serialNumber: serial,
            maxPairedDevices: maxDevices,
            connectedDeviceCount: Int(connState.parameters.first ?? 0) & 0x0F,
            firmwareVersion: firmware
        )
    }

    /// HID++ 1.0 fallback: read firmware via register 0xF1. Sub-registers:
    ///   0x01 → main fw: response params = [0x01, major(BCD), minor(BCD)]
    ///   0x02 → build: response params = [0x02, build_hi, build_lo]
    /// Both come back as short responses on Unifying receivers.
    private func readFirmwareF1() async -> String? {
        guard let main = try? await request(
            kind: .short, subID: .getRegisterShort,
            register: .firmwareInfo,
            parameters: [0x01, 0, 0]
        ) else { return nil }
        let m = main.parameters
        guard m.count >= 3, m[0] == 0x01 else { return nil }
        let base = String(format: "%02X.%02X", m[1], m[2])

        if let buildResp = try? await request(
            kind: .short, subID: .getRegisterShort,
            register: .firmwareInfo,
            parameters: [0x02, 0, 0]
        ) {
            let b = buildResp.parameters
            if b.count >= 3, b[0] == 0x02 {
                let build = (Int(b[1]) << 8) | Int(b[2])
                return "\(base).B\(String(format: "%04X", build))"
            }
        }
        return base
    }

    /// HID++ 2.0 readout of DeviceInformation feature (0x0003).
    private func readDeviceInformationV2() async throws -> (serialNumber: String?, firmwareVersion: String?) {
        let idx = try await featureIndex(for: .deviceInformation)

        // Function 0 GetDeviceInfo:
        //   response[0] = entityCount, [1..4] = unitId, [5] = transport bits,
        //   [6..7] = modelId, [8..9] = extModelId + capabilities
        let info = try await featureRequest(featureIndex: idx, function: 0)
        let entityCount = Int(info.parameters[0])

        // Function 1 GetFwInfo(entity=0) → main firmware. Response:
        //   [0] = type, [1..3] = prefix (3 ASCII chars), [4] = major (BCD),
        //   [5] = minor (BCD), [6..7] = build (big-endian).
        var firmware: String? = nil
        if entityCount > 0,
           let fw = try? await featureRequest(featureIndex: idx, function: 1, parameters: [0]) {
            let p = fw.parameters
            if p.count >= 8 {
                let prefix = String(bytes: [p[1], p[2], p[3]], encoding: .ascii)?
                    .trimmingCharacters(in: .controlCharacters) ?? ""
                let build = (Int(p[6]) << 8) | Int(p[7])
                firmware = "\(prefix) \(hexBCD(p[4])).\(hexBCD(p[5])).B\(String(format: "%04X", build))"
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        // Function 4 GetSerialNumber → 12-char ASCII serial (some firmwares
        // return 16). Strip nuls.
        var serial: String? = nil
        if let s = try? await featureRequest(featureIndex: idx, function: 4) {
            let bytes = Array(s.parameters.prefix(16)).filter { $0 != 0 }
            if let str = String(bytes: bytes, encoding: .ascii), !str.isEmpty {
                serial = str.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return (serial, firmware)
    }
}

private func hexBCD(_ b: UInt8) -> String { String(format: "%02X", b) }

/// Coarse summary of a paired device discovered by pinging its slot.
public struct PairedDeviceSummary: Sendable, Hashable {
    public let slot: Int
    public let hidppMajor: UInt8
    public let hidppMinor: UInt8

    public var hidppVersion: String { "\(hidppMajor).\(hidppMinor)" }
}

/// Decoded receiver information. All fields optional because byte layouts
/// vary across receiver generations and we'd rather show "unknown" than fail.
public struct ReceiverInfo: Sendable, Hashable {
    public let serialNumber: String?
    public let maxPairedDevices: Int?
    public let connectedDeviceCount: Int?
    public let firmwareVersion: String?

    /// HID++ 1.0 register 0xB5 sub 0x03 response:
    ///   params[0]=0x03, params[1..4]=serial (BE), params[5]=max paired devices.
    static func decodeReceiverInfoRegister(_ report: HIDPPReport) -> (serial: String?, maxDevices: Int?) {
        let p = report.parameters
        guard p.count >= 6, p[0] == HIDPP10.PairingInfoSub.receiverInformation else {
            return (nil, nil)
        }
        let serial = String(format: "%02X%02X%02X%02X", p[1], p[2], p[3], p[4])
        let raw = Int(p[5])
        return (serial, raw > 0 && raw <= 8 ? raw : nil)
    }

    /// HID++ 1.0 register 0xB5 sub 0x02 response:
    ///   params[0]=0x02, params[1]=major BCD, params[2]=minor BCD, params[3..4]=build BE.
    static func decodeFirmwareRegister(_ report: HIDPPReport) -> String? {
        let f = report.parameters
        guard f.count >= 5, f[0] == HIDPP10.PairingInfoSub.firmwareVersion else { return nil }
        let build = (Int(f[3]) << 8) | Int(f[4])
        return String(format: "%02X.%02X.B%04X", f[1], f[2], build)
    }
}
