import Foundation
import Observation
import HIDPP
import HIDTransport

/// Top-level app state. Owns the long-lived `HIDManager` and a
/// `ReceiverViewModel` for every receiver currently plugged in.
@MainActor
@Observable
final class AppState {
    private(set) var receivers: [ReceiverViewModel] = []
    var selectedReceiverLocationID: UInt64? = nil
    var lastError: String? = nil

    /// Single, app-lifetime HIDManager so handles vended at discovery time
    /// stay valid for the lifetime of any `ReceiverViewModel`.
    private let manager = HIDManager()

    init() {
        refresh()
    }

    func refresh() {
        do {
            let found = try ReceiverDiscovery.find(using: manager)
            // Preserve existing view models when the same receiver is still
            // present (avoids reopening HID++ interfaces on every refresh).
            let existing = Dictionary(uniqueKeysWithValues: receivers.map { ($0.locationID, $0) })
            receivers = found.map { discovered in
                existing[discovered.locationID] ?? ReceiverViewModel(discovered: discovered)
            }
            if selectedReceiverLocationID == nil ||
               !receivers.contains(where: { $0.locationID == selectedReceiverLocationID }) {
                selectedReceiverLocationID = receivers.first?.locationID
            }
        } catch {
            lastError = "discovery failed: \(error)"
        }
    }

    var selectedReceiver: ReceiverViewModel? {
        guard let id = selectedReceiverLocationID else { return nil }
        return receivers.first(where: { $0.locationID == id })
    }
}
