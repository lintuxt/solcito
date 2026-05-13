import Foundation
import HIDTransport
import os

/// High-level handle for a Logitech receiver. Wraps the HID++ interface and
/// exposes typed operations (read receiver info, list paired devices, …).
///
/// Concurrency model: a single internal `dispatchTask` consumes
/// `device.inputReports` for the lifetime of the open device. Every parsed
/// report is routed to either (a) a pending `send()` waiter matched on
/// sub-ID + address (with 1.0/2.0 error correlation) or (b) all current
/// `notifications` subscribers as a multicast. No caller ever iterates the
/// underlying `device.inputReports` directly, so single-consumer
/// `AsyncStream` semantics don't burn us — multiple concurrent `send()`
/// calls and notification observers all coexist cleanly.
public final class Receiver: @unchecked Sendable {

    public let id: ReceiverID
    public let interface: HIDDeviceInfo
    private let device: HIDDevice

    private struct Waiter: Sendable {
        let id: UUID
        let expectedSubID: UInt8
        let expectedAddress: UInt8
        let continuation: CheckedContinuation<HIDPPReport, Error>
    }

    private struct State: Sendable {
        var waiters: [Waiter] = []
        var subscribers: [UUID: AsyncStream<HIDPPReport>.Continuation] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private var dispatchTask: Task<Void, Never>? = nil

    public init(id: ReceiverID, hidppDevice: HIDDevice) {
        self.id = id
        self.interface = hidppDevice.info
        self.device = hidppDevice
    }

    public func open() throws {
        try device.open()
        startDispatching()
    }

    public func close() {
        let task = dispatchTask
        dispatchTask = nil
        task?.cancel()

        // Drain pending state: resume waiters with cancellation, finish
        // subscribers cleanly so anyone iterating exits their for-await.
        let (pending, subs) = state.withLock { state -> ([Waiter], [AsyncStream<HIDPPReport>.Continuation]) in
            let p = state.waiters
            let s = Array(state.subscribers.values)
            state.waiters.removeAll()
            state.subscribers.removeAll()
            return (p, s)
        }

        for w in pending { w.continuation.resume(throwing: CancellationError()) }
        for s in subs { s.finish() }

        device.close()
    }

    private func startDispatching() {
        dispatchTask = Task { [weak self] in
            guard let self else { return }
            for await raw in self.device.inputReports {
                if Task.isCancelled { break }
                guard let report = HIDPPReport.parse(reportID: raw.reportID, payload: raw.payload) else {
                    HIDPPTrace.log("  ? unparseable id=\(HIDPPTrace.hex(raw.reportID)) len=\(raw.payload.count)")
                    continue
                }
                self.dispatch(report)
            }
            HIDPPTrace.log("dispatcher: input stream ended")
        }
    }

    private enum DispatchAction {
        case resumeSuccess(Waiter)
        case resumeError(Waiter, HIDPPError)
        case broadcast([AsyncStream<HIDPPReport>.Continuation])
    }

    private func dispatch(_ report: HIDPPReport) {
        let action: DispatchAction = state.withLock { state in
            for (i, w) in state.waiters.enumerated() {
                // Direct match.
                if report.subID == w.expectedSubID && report.address == w.expectedAddress {
                    state.waiters.remove(at: i)
                    return .resumeSuccess(w)
                }
                // Error correlation (1.0: subID=0x8F; 2.0: subID=0xFF;
                // both carry original sub/addr in address + parameters[0]).
                if report.isError, let err = report.errorPayload,
                   err.originalSubID == w.expectedSubID,
                   err.originalAddress == w.expectedAddress {
                    state.waiters.remove(at: i)
                    return .resumeError(w, HIDPPError.protocolError(
                        originalSubID: err.originalSubID,
                        register: err.originalAddress,
                        code: err.code
                    ))
                }
            }
            return .broadcast(Array(state.subscribers.values))
        }

        switch action {
        case .resumeSuccess(let w):
            HIDPPTrace.log("← match → waiter sub=\(HIDPPTrace.hex(w.expectedSubID)) addr=\(HIDPPTrace.hex(w.expectedAddress)) params=[\(HIDPPTrace.hex(report.parameters))]")
            w.continuation.resume(returning: report)
        case .resumeError(let w, let e):
            HIDPPTrace.log("× err  → waiter sub=\(HIDPPTrace.hex(w.expectedSubID)) addr=\(HIDPPTrace.hex(w.expectedAddress)) code=\(HIDPPTrace.hex(report.errorPayload?.code ?? 0))")
            w.continuation.resume(throwing: e)
        case .broadcast(let subs):
            HIDPPTrace.log("· notif \(HIDPPTrace.subIDLabel(report.subID)) dev=\(HIDPPTrace.hex(report.deviceIndex)) addr=\(HIDPPTrace.hex(report.address)) → \(subs.count) sub(s)")
            for s in subs { s.yield(report) }
        }
    }

    /// Multicast stream of notifications (reports not matched to a pending
    /// `send()` waiter). Every active subscriber receives every event.
    /// Subscribers are added/removed automatically as their for-await
    /// iterators come and go.
    public var notifications: AsyncStream<HIDPPReport> {
        let subscriberID = UUID()
        return AsyncStream { continuation in
            self.state.withLock { state in
                state.subscribers[subscriberID] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.state.withLock { state in
                    state.subscribers.removeValue(forKey: subscriberID)
                }
            }
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
    /// Open the pairing lock so a new device announcing itself within
    /// `timeoutSeconds` gets attached. Action byte is **0x01** per Solaar's
    /// `set_lock(lock_closed=False)` — the previous code shipped 0x02 here
    /// (Solaar's "close" action), which is why no device ever actually
    /// paired through solcito.
    public func beginPairing(timeoutSeconds: UInt8 = 30, slot: UInt8 = 0) async throws {
        HIDPPTrace.log("┌─ beginPairing(timeout: \(timeoutSeconds)s, slot: \(slot))")
        _ = try await request(
            kind: .short,
            subID: .setRegisterShort,
            register: .receiverPairing,
            parameters: [0x01, slot, timeoutSeconds]
        )
        HIDPPTrace.log("└─ beginPairing OK")
    }

    /// Close the pairing lock (cancel an open window). Action byte is **0x02**
    /// per Solaar's `set_lock(lock_closed=True)`.
    public func cancelPairing() async throws {
        HIDPPTrace.log("┌─ cancelPairing()")
        _ = try await request(
            kind: .short,
            subID: .setRegisterShort,
            register: .receiverPairing,
            parameters: [0x02, 0x00, 0x00]
        )
        HIDPPTrace.log("└─ cancelPairing OK")
    }

    /// Unpair the device at the given slot (1...maxSlots). Solaar source:
    /// `write_register(Registers.RECEIVER_PAIRING, 0x03, slot)`.
    public func unpair(slot: UInt8) async throws {
        HIDPPTrace.log("┌─ unpair(slot: \(slot))")
        _ = try await request(
            kind: .short,
            subID: .setRegisterShort,
            register: .receiverPairing,
            parameters: [0x03, slot, 0x00]
        )
        HIDPPTrace.log("└─ unpair OK")
    }

    // MARK: - Paired-device discovery

    /// Ping each slot 1..`maxSlots` and return summary info for the ones that
    /// answer. Uses HID++ 2.0 Root.GetProtocolVersion (feature index 0,
    /// function 1) — works regardless of whether the receiver itself speaks
    /// HID++ 2.0, because the paired devices answer for themselves.
    /// Probe every slot 1..`maxSlots` and report what's there. Distinguishes
    /// three outcomes: an empty slot (receiver returns `unsupported` error
    /// 0x09 immediately), a paired-but-silent slot (receiver forwards to the
    /// device, device doesn't answer in time — usually asleep), or a
    /// paired-and-responding slot (HID++ 2.0 ping echoes back).
    public func probeSlots(maxSlots: Int = 6, perSlotTimeout: Duration = .milliseconds(400)) async -> [SlotProbe] {
        HIDPPTrace.log("┌─ probeSlots(maxSlots: \(maxSlots))")
        var results: [SlotProbe] = []
        for slot in 1...UInt8(maxSlots) {
            results.append(SlotProbe(slot: Int(slot), status: await probeStatus(of: slot, timeout: perSlotTimeout)))
        }
        HIDPPTrace.log("└─ probeSlots done")
        return results
    }

    private func probeStatus(of slot: UInt8, timeout: Duration) async -> SlotStatus {
        HIDPPTrace.log("  probe slot \(slot)")
        let pingByte: UInt8 = 0x5A
        do {
            let resp = try await featureRequest(
                deviceIndex: slot,
                featureIndex: 0, function: 1,
                parameters: [0x00, 0x00, pingByte],
                kind: .short,
                timeout: timeout
            )
            let p = resp.parameters
            let major = p.count >= 1 ? p[0] : 0
            let minor = p.count >= 2 ? p[1] : 0
            return .respondingHIDPP(major: major, minor: minor)
        } catch HIDPPError.protocolError(_, _, 0x09) {
            return .empty
        } catch {
            return .silent
        }
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
        let waiterID = UUID()
        let expectedSubID = outgoing.subID
        let expectedAddress = outgoing.address

        HIDPPTrace.log("→ send \(HIDPPTrace.subIDLabel(expectedSubID)) "
            + "dev=\(HIDPPTrace.hex(outgoing.deviceIndex)) "
            + "addr=\(HIDPPTrace.hex(expectedAddress)) "
            + "params=[\(HIDPPTrace.hex(outgoing.parameters))] "
            + "kind=\(outgoing.kind) timeout=\(timeout)")

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<HIDPPReport, Error>) in
            // Register waiter BEFORE sending so a fast response isn't missed.
            state.withLock { state in
                state.waiters.append(Waiter(
                    id: waiterID,
                    expectedSubID: expectedSubID,
                    expectedAddress: expectedAddress,
                    continuation: cont
                ))
            }

            // Independent timeout task. If the dispatcher already removed
            // the waiter (response arrived), this is a no-op.
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self else { return }
                let removed = self.state.withLock { state -> Waiter? in
                    guard let i = state.waiters.firstIndex(where: { $0.id == waiterID }) else { return nil }
                    return state.waiters.remove(at: i)
                }
                if let w = removed {
                    HIDPPTrace.log("⏰ timeout: \(HIDPPTrace.subIDLabel(expectedSubID)) addr=\(HIDPPTrace.hex(expectedAddress))")
                    w.continuation.resume(throwing: HIDPPError.timeout)
                }
            }

            // Now actually send. If the transport call fails synchronously,
            // unregister the waiter and resume with that error.
            do {
                try device.send(reportID: outgoing.kind.rawValue, outgoing.serializedPayload())
            } catch {
                let removed = state.withLock { state -> Waiter? in
                    guard let i = state.waiters.firstIndex(where: { $0.id == waiterID }) else { return nil }
                    return state.waiters.remove(at: i)
                }
                if let w = removed { w.continuation.resume(throwing: error) }
            }
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

/// What we found when probing a single slot.
public enum SlotStatus: Sendable, Hashable {
    /// Receiver reported "unsupported" — no device paired at this slot.
    case empty
    /// Slot has a device paired but it didn't answer the ping (usually asleep).
    case silent
    /// Slot has a device paired and it answered the HID++ 2.0 ping.
    case respondingHIDPP(major: UInt8, minor: UInt8)
}

public struct SlotProbe: Sendable, Hashable {
    public let slot: Int
    public let status: SlotStatus

    public var isPaired: Bool {
        switch status {
        case .empty: return false
        case .silent, .respondingHIDPP: return true
        }
    }
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
