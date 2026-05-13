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

    func loadInfo() async {
        guard hasHIDPPInterface else {
            lastError = "this receiver doesn't expose a HID++ interface"
            return
        }
        isLoadingInfo = true
        defer { isLoadingInfo = false }
        do {
            let r = try ensureOpen()
            async let info = r.info()
            async let devices = r.pairedDevices()
            self.info = try await info
            self.pairedDevices = await devices
            self.lastError = nil
        } catch {
            self.lastError = "\(error)"
        }
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
            consumer.cancel()
            try? await r.cancelPairing()
            pairingLog.append("Pairing window closed.")
        } catch {
            pairingLog.append("Error: \(error)")
            lastError = "\(error)"
        }

        // Refresh post-pair so any new device shows in the list.
        await loadInfo()
    }

    func unpair(slot: Int) async {
        guard hasHIDPPInterface else { return }
        do {
            let r = try ensureOpen()
            try await r.unpair(slot: UInt8(slot))
            await loadInfo()
        } catch {
            lastError = "\(error)"
        }
    }

    deinit {
        // Receiver/HIDDevice will close themselves via their own deinit; we
        // just clear the optional. Don't touch MainActor state from deinit.
    }
}
