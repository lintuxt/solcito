import Foundation
import Observation
import HIDPP
import HIDTransport

@MainActor
@Observable
final class ReceiverViewModel: Identifiable {

    let discovered: DiscoveredReceiver
    var info: ReceiverInfo? = nil
    var pairedDevices: [PairedDeviceSummary] = []
    var pairingLog: [String] = []
    var isLoadingInfo = false
    var isPairing = false
    var lastError: String? = nil

    private var receiver: Receiver? = nil

    var locationID: UInt64 { discovered.locationID }
    nonisolated var id: UInt64 { discovered.locationID }
    var hasHIDPPInterface: Bool { discovered.hidppInterface != nil }

    init(discovered: DiscoveredReceiver) {
        self.discovered = discovered
    }

    private func ensureOpen() throws -> Receiver {
        if let r = receiver { return r }
        guard let hidpp = discovered.hidppInterface else {
            throw HIDPPError.noHIDPPInterface
        }
        let device = HIDDevice(handle: hidpp)
        let r = Receiver(id: discovered.id, hidppDevice: device)
        try r.open()
        receiver = r
        return r
    }

    /// Light-touch load: just the receiver-info reads. Skips the 6-slot
    /// HID++ 2.0 ping sweep because chaining ~12 requests in rapid
    /// succession on this firmware wedges the receiver's state machine —
    /// the next request (e.g. `beginPairing`) then silently times out.
    /// Use `refreshAll()` when slot discovery is explicitly desired.
    func loadInfo() async {
        guard hasHIDPPInterface else {
            lastError = "this receiver doesn't expose a HID++ interface"
            return
        }
        isLoadingInfo = true
        defer { isLoadingInfo = false }
        do {
            let r = try ensureOpen()
            self.info = try await r.info()
            self.lastError = nil
        } catch {
            self.lastError = "\(error)"
        }
    }

    /// Ping all slots 1..6 looking for paired devices that answer HID++ 2.0.
    /// Asleep / HID++ 1.0-only devices won't respond. Always user-triggered.
    func discoverPairedDevices() async {
        guard hasHIDPPInterface else { return }
        isLoadingInfo = true
        defer { isLoadingInfo = false }
        do {
            let r = try ensureOpen()
            self.pairedDevices = await r.pairedDevices()
        } catch {
            self.lastError = "\(error)"
        }
    }

    /// Full refresh: info + paired-device discovery, sequentially.
    func refreshAll() async {
        await loadInfo()
        await discoverPairedDevices()
    }

    func startPairing(timeoutSeconds: UInt8 = 30) async {
        guard hasHIDPPInterface, !isPairing else { return }
        isPairing = true
        pairingLog = []
        defer { isPairing = false }

        do {
            let r = try ensureOpen()
            try await r.beginPairing(timeoutSeconds: timeoutSeconds)
            pairingLog.append("Pairing window open for \(timeoutSeconds)s. Press the pair button on your device.")

            let consumer = Task { [weak self] in
                for await event in r.pairingEvents {
                    let line = formatPairingEvent(event)
                    await MainActor.run { self?.pairingLog.append(line) }
                }
            }

            try? await Task.sleep(for: .seconds(Int(timeoutSeconds)))
            // Cancel AND wait for the consumer to actually exit before we
            // start another request on the device — otherwise its iterator
            // on device.inputReports overlaps with cancelPairing's iterator
            // and they steal each other's events (manifests as
            // "HID++ request timed out" on subsequent pair attempts).
            consumer.cancel()
            _ = await consumer.value
            try? await r.cancelPairing()
            pairingLog.append("Pairing window closed.")
        } catch {
            pairingLog.append("Error: \(error)")
            lastError = "\(error)"
        }

        // After a pair attempt, refresh receiver info AND ping slots so a
        // newly-paired device shows up. This runs whether pair succeeded
        // or not; on failure it just reloads stale state, but at least
        // doesn't compound the wedge by running before the next attempt.
        await refreshAll()
    }

    func unpair(slot: Int) async {
        guard hasHIDPPInterface else { return }
        do {
            let r = try ensureOpen()
            try await r.unpair(slot: UInt8(slot))
            await refreshAll()
        } catch {
            lastError = "\(error)"
        }
    }

    deinit {
        // Receiver/HIDDevice will close themselves via their own deinit; we
        // just clear the optional. Don't touch MainActor state from deinit.
    }
}
