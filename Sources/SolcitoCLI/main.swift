import Foundation
import HIDPP
import HIDTransport

@main
struct SolcitoCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        switch args.first {
        case nil, "list":
            await runList()
        case "info":
            await runInfo(index: args.dropFirst().first.flatMap(Int.init))
        case "pair":
            let rest = Array(args.dropFirst())
            await runPair(
                receiverIndex: rest.first.flatMap(Int.init),
                timeout: rest.dropFirst().first.flatMap(UInt8.init) ?? 30
            )
        case "unpair":
            let rest = Array(args.dropFirst())
            guard let slot = rest.first.flatMap(UInt8.init), slot > 0 else {
                FileHandle.standardError.write(Data("usage: solcito-cli unpair <slot 1..6> [receiver]\n".utf8))
                exit(2)
            }
            await runUnpair(slot: slot, receiverIndex: rest.dropFirst().first.flatMap(Int.init))
        case "devices":
            await runDevices(receiverIndex: args.dropFirst().first.flatMap(Int.init))
        case "wedge":
            // Reproduces what the SwiftUI app does on view-appear: info()
            // then pairedDevices() then beginPairing. The app's pair fails
            // after this sequence; CLI's solo pair works. This command lets
            // us see — with SOLCITO_HIDPP_TRACE=1 — exactly where the wedge
            // shows up in the trace.
            let rest = Array(args.dropFirst())
            await runWedge(
                receiverIndex: rest.first.flatMap(Int.init),
                pairTimeout: rest.dropFirst().first.flatMap(UInt8.init) ?? 5
            )
        case "--help", "-h", "help":
            printUsage()
        case let other?:
            FileHandle.standardError.write(Data("unknown command: \(other)\n".utf8))
            exit(2)
        }
    }
}

private func printUsage() {
    print("""
    solcito-cli — manage Logitech receivers on macOS

    USAGE:
      solcito-cli [list]                List connected Logitech receivers (default)
      solcito-cli info [N]              Show HID++ info for receiver N (default: 0)
      solcito-cli pair [N] [timeout]    Enter pairing mode on receiver N (default: 0)
                                        for `timeout` seconds (default: 30).
                                        Press the pair button on your device.
      solcito-cli unpair <slot> [N]     Unpair the device at slot (1..6) on receiver N.
      solcito-cli devices [N]           List paired devices on receiver N (HID++ 2.0 ping).
      solcito-cli wedge [N] [timeout]   Diagnostic: run info() + pairedDevices() then
                                        attempt beginPairing in one process. Used with
                                        SOLCITO_HIDPP_TRACE=1 to reproduce app behavior.
      solcito-cli help                  Show this help
    """)
}

// MARK: - list

private func runList() async {
    let receivers: [DiscoveredReceiver]
    do {
        receivers = try ReceiverDiscovery.find(using: HIDManager())
    } catch {
        die("discovery failed: \(error)")
    }

    if receivers.isEmpty {
        print("No Logitech receivers found.")
        return
    }

    print("Found \(receivers.count) receiver\(receivers.count == 1 ? "" : "s"):\n")
    for (idx, r) in receivers.enumerated() {
        print("[\(idx)] \(r.id.name) (\(r.id.kind.displayName))")
        print("    USB:        VID=0x\(hex4(r.id.vendorID))  PID=0x\(hex4(r.id.productID))")
        print("    Location:   0x\(String(r.locationID, radix: 16))")
        print("    HID++:      \(r.hidppInterface == nil ? "not exposed" : "available")")
        print("    Pairable:   \(r.id.kind.supportsPairing ? "yes" : "no")")
        print()
    }
}

// MARK: - info

private func runInfo(index: Int?) async {
    let manager = HIDManager()
    let receivers: [DiscoveredReceiver]
    do {
        receivers = try ReceiverDiscovery.find(using: manager)
    } catch {
        die("discovery failed: \(error)")
    }
    guard !receivers.isEmpty else { die("No Logitech receivers found.") }
    let chosenIndex = index ?? 0
    guard chosenIndex >= 0, chosenIndex < receivers.count else {
        die("receiver index \(chosenIndex) out of range (0..<\(receivers.count))")
    }
    let r = receivers[chosenIndex]
    guard let hidpp = r.hidppInterface else {
        die("receiver [\(chosenIndex)] does not expose a HID++ interface")
    }

    print("Receiver [\(chosenIndex)]: \(r.id.name) (\(r.id.kind.displayName))")
    print("  Location: 0x\(String(r.locationID, radix: 16))")
    print("  USB:      VID=0x\(hex4(r.id.vendorID))  PID=0x\(hex4(r.id.productID))")

    let device = HIDDevice(handle: hidpp)
    let receiver = Receiver(id: r.id, hidppDevice: device)
    defer { receiver.close() }

    do {
        try receiver.open()
    } catch {
        die("could not open HID++ interface: \(error)\n  (try running with sudo, or check that no other process — including Logitech G HUB / Solaar — has the receiver open)")
    }

    do {
        let info = try await receiver.info()
        print("  Firmware: \(info.firmwareVersion ?? "unknown")")
        print("  Serial:   \(info.serialNumber ?? "unknown")")
        print("  Max devices:        \(info.maxPairedDevices.map(String.init) ?? "unknown")")
        print("  Connected devices:  \(info.connectedDeviceCount.map(String.init) ?? "unknown")")
    } catch {
        die("info read failed: \(error)")
    }
}

// MARK: - pair / unpair

private func openHIDPP(receiverIndex: Int?) async -> (DiscoveredReceiver, Receiver) {
    let manager = HIDManager()
    _ = manager  // retain for handle lifetime
    let receivers: [DiscoveredReceiver]
    do {
        receivers = try ReceiverDiscovery.find(using: manager)
    } catch {
        die("discovery failed: \(error)")
    }
    guard !receivers.isEmpty else { die("No Logitech receivers found.") }
    let idx = receiverIndex ?? 0
    guard idx >= 0, idx < receivers.count else {
        die("receiver index \(idx) out of range (0..<\(receivers.count))")
    }
    let r = receivers[idx]
    guard let hidpp = r.hidppInterface else {
        die("receiver [\(idx)] does not expose a HID++ interface")
    }
    let device = HIDDevice(handle: hidpp)
    let receiver = Receiver(id: r.id, hidppDevice: device)
    do {
        try receiver.open()
    } catch {
        die("could not open HID++ interface: \(error)\n  (try quitting Logi Options+ or G HUB)")
    }
    return (r, receiver)
}

private func runPair(receiverIndex: Int?, timeout: UInt8) async {
    let (r, receiver) = await openHIDPP(receiverIndex: receiverIndex)
    defer { receiver.close() }

    print("Receiver: \(r.id.name) (\(r.id.kind.displayName))")
    print("Opening pairing window for \(timeout) seconds…")
    print("→ Press the pair button on the Logitech device you want to pair.\n")

    do {
        try await receiver.beginPairing(timeoutSeconds: timeout)
    } catch {
        die("could not start pairing: \(error)")
    }

    let deadline = ContinuousClock().now.advanced(by: .seconds(Int(timeout) + 2))
    let watcher = Task {
        for await event in receiver.pairingEvents {
            switch event {
            case .lockOpened:
                print("  → lock opened (receiver discoverable)")
            case .lockClosed(let success, let code):
                if success {
                    print("  → lock closed")
                } else {
                    print("  → lock closed with error code 0x\(String(format: "%02X", code ?? 0))")
                }
            case .deviceConnected(let slot, let wpid, let kind):
                let wpidStr = wpid.map { String(format: "0x%04X", $0) } ?? "?"
                let kindStr = kind.map(\.description) ?? "Unknown"
                print("  ✓ slot \(slot): \(kindStr) connected (WPID \(wpidStr))")
            case .deviceDisconnected(let slot):
                print("  ✗ slot \(slot): disconnected")
            case .raw(let r):
                let hex = r.parameters.map { String(format: "%02X", $0) }.joined(separator: " ")
                print("  · raw  dev=\(String(format: "0x%02X", r.deviceIndex))  " +
                      "sub=\(String(format: "0x%02X", r.subID))  " +
                      "addr=\(String(format: "0x%02X", r.address))  [\(hex)]")
            }
        }
    }

    while ContinuousClock().now < deadline {
        try? await Task.sleep(for: .milliseconds(250))
    }
    watcher.cancel()

    // Best-effort: close the pairing lock if it's still open.
    try? await receiver.cancelPairing()
    print("\nPairing window closed.")
}

private func runDevices(receiverIndex: Int?) async {
    let (r, receiver) = await openHIDPP(receiverIndex: receiverIndex)
    defer { receiver.close() }

    print("Receiver: \(r.id.name) (\(r.id.kind.displayName))")
    print("Pinging slots 1..6 (HID++ 2.0 Root.GetProtocolVersion)…\n")

    let devices = await receiver.pairedDevices()
    if devices.isEmpty {
        print("No paired devices responded.")
        print("(All slots either empty, asleep, or this receiver doesn't relay HID++ 2.0 to its devices.)")
        return
    }
    for d in devices {
        print("  Slot \(d.slot): HID++ \(d.hidppVersion)")
    }
}

private func runWedge(receiverIndex: Int?, pairTimeout: UInt8) async {
    let (r, receiver) = await openHIDPP(receiverIndex: receiverIndex)
    defer { receiver.close() }

    print("Receiver: \(r.id.name) (\(r.id.kind.displayName))")
    print()
    print("step 1/3: info()")
    do {
        let info = try await receiver.info()
        print("  firmware:  \(info.firmwareVersion ?? "unknown")")
        print("  serial:    \(info.serialNumber ?? "unknown")")
        print("  max slots: \(info.maxPairedDevices.map(String.init) ?? "unknown")")
        print("  connected: \(info.connectedDeviceCount.map(String.init) ?? "unknown")")
    } catch {
        print("  ✗ \(error)")
    }
    print()
    print("step 2/3: pairedDevices() (slot ping sweep)")
    let devices = await receiver.pairedDevices()
    if devices.isEmpty {
        print("  no responses")
    } else {
        for d in devices { print("  slot \(d.slot): HID++ \(d.hidppVersion)") }
    }
    print()
    print("step 3/3: beginPairing(timeout: \(pairTimeout)s)")
    do {
        try await receiver.beginPairing(timeoutSeconds: pairTimeout)
        print("  ✓ pairing window open. Letting it run \(pairTimeout)s…")
        try? await Task.sleep(for: .seconds(Int(pairTimeout)))
        try? await receiver.cancelPairing()
        print("  pairing window closed.")
    } catch {
        print("  ✗ \(error)")
    }
}

private func runUnpair(slot: UInt8, receiverIndex: Int?) async {
    let (r, receiver) = await openHIDPP(receiverIndex: receiverIndex)
    defer { receiver.close() }

    print("Receiver: \(r.id.name) — unpairing slot \(slot)…")
    do {
        try await receiver.unpair(slot: slot)
        print("Done.")
    } catch {
        die("unpair failed: \(error)")
    }
}

// MARK: - helpers

private func hex4(_ n: Int) -> String { String(format: "%04X", n) }

private func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("error: \(msg)\n".utf8))
    exit(1)
}
