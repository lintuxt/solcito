import Foundation
import HIDPP
import HIDTransport

@main
struct SolcitoCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        switch args.first {
        case nil:
            await showStatus()
        case "pair":
            await runPair()
        case "unpair":
            guard let slot = args.dropFirst().first.flatMap(UInt8.init), (1...6).contains(slot) else {
                stderr("Usage: solcito unpair <slot>")
                stderr("       Slot is the number shown next to the device in `solcito`.")
                exit(2)
            }
            await runUnpair(slot: slot)
        case "help", "-h", "--help":
            printHelp()
        case let other?:
            stderr("Unknown command: \(other)")
            stderr("Run `solcito help` to see available commands.")
            exit(2)
        }
    }
}

// MARK: - help

private func printHelp() {
    print("""
    solcito — manage your Logitech wireless devices on macOS

    USAGE
      solcito                  Show your receiver and the devices paired to it.
      solcito pair             Add a new device. Press the small "Connect"
                               button on the device when prompted.
      solcito unpair <slot>    Remove the device in the given slot (1–6).
                               You can find slot numbers in `solcito`.
      solcito help             Show this help.

    Most Logitech mice and keyboards have a small "Connect" button on the
    underside that puts them into pairing mode. Press it within 30 seconds
    of starting `solcito pair`.
    """)
}

// MARK: - default: status

private func showStatus() async {
    let manager = HIDManager()
    let receivers: [DiscoveredReceiver]
    do {
        receivers = try ReceiverDiscovery.find(using: manager)
    } catch {
        die("Couldn't scan for receivers. (\(error))")
    }

    guard !receivers.isEmpty else {
        print("No Logitech receiver found.")
        print("Plug in your Logitech USB receiver, then run `solcito` again.")
        return
    }

    let prefixed = receivers.count > 1
    for (index, r) in receivers.enumerated() {
        if index > 0 { print() }
        await printReceiverStatus(r, prefix: prefixed ? "[\(index + 1)] " : nil)
    }

    print()
    if prefixed {
        print("  solcito pair             Pair a new device (you'll be asked which receiver)")
        print("  solcito unpair <slot>    Remove a device (you'll be asked which receiver)")
    } else {
        print("  solcito pair             Pair a new device")
        print("  solcito unpair <slot>    Remove a device")
    }
}

private func printReceiverStatus(_ r: DiscoveredReceiver, prefix: String?) async {
    print("\(prefix ?? "")\(r.id.name)")
    let indent = String(repeating: " ", count: (prefix?.count ?? 0))

    guard let hidpp = r.hidppInterface else {
        print("\(indent)  This receiver doesn't support pairing through solcito.")
        return
    }

    let device = HIDDevice(handle: hidpp)
    let receiver = Receiver(id: r.id, hidppDevice: device)
    defer { receiver.close() }

    do {
        try receiver.open()
    } catch {
        print("\(indent)  Couldn't open the receiver.")
        print("\(indent)  Quit Logi Options+ or Logitech G Hub if they're running and try again.")
        return
    }

    let probes = await receiver.probeSlots()
    let paired = probes.filter { $0.isPaired }
    if paired.isEmpty {
        print("\(indent)  No paired devices.")
        return
    }
    for p in paired {
        switch p.status {
        case .respondingHIDPP:
            print("\(indent)  • Slot \(p.slot): paired")
        case .silent:
            print("\(indent)  • Slot \(p.slot): paired (currently asleep)")
        case .empty:
            break
        }
    }
}

// MARK: - pair

private func runPair() async {
    let manager = HIDManager()
    let receivers: [DiscoveredReceiver]
    do {
        receivers = try ReceiverDiscovery.find(using: manager)
    } catch {
        die("Couldn't scan for receivers. (\(error))")
    }
    guard !receivers.isEmpty else {
        die("No Logitech receiver found. Plug in your USB receiver and try again.")
    }
    let r = await chooseReceiver(from: receivers, prompt: "Which receiver should I pair to?")
    guard let hidpp = r.hidppInterface else {
        die("\(r.id.name) doesn't support pairing.")
    }
    guard r.id.kind.supportsPairing else {
        die("\(r.id.name) can't pair new devices (this receiver type is fixed).")
    }

    let device = HIDDevice(handle: hidpp)
    let receiver = Receiver(id: r.id, hidppDevice: device)
    defer { receiver.close() }
    do {
        try receiver.open()
    } catch {
        die("Couldn't open the receiver. Quit Logi Options+ or Logitech G Hub and try again.")
    }

    let timeoutSeconds: UInt8 = 30
    print("Opening pairing window on \(r.id.name)…")
    print("Press the small \"Connect\" button on your device now (within \(timeoutSeconds) seconds).")
    print()

    do {
        try await receiver.beginPairing(timeoutSeconds: timeoutSeconds)
    } catch {
        die("Couldn't open the pairing window. (\(error))")
    }

    // Listen for events until we see a device get paired or the window times
    // out. We early-exit on the first deviceConnected event so the user
    // isn't stuck waiting for the full window.
    let deadline = ContinuousClock().now.advanced(by: .seconds(Int(timeoutSeconds) + 2))
    var paired: (slot: Int, kind: PairedDeviceKind?)? = nil
    var pairError: UInt8? = nil

    eventLoop: for await event in receiver.pairingEvents {
        if ContinuousClock().now >= deadline { break }
        switch event {
        case .deviceConnected(let slot, _, let kind):
            // The receiver sends two CONNECT_NOTIFs (discovered + authenticated).
            // The first one already has the right slot/kind, so just take it.
            if paired == nil {
                paired = (slot, kind)
                print("✓ \(kind?.description ?? "Device") paired in slot \(slot).")
                break eventLoop
            }
        case .lockClosed(let success, let code):
            if !success { pairError = code }
            break eventLoop
        case .lockOpened, .deviceDisconnected, .raw:
            continue
        }
    }

    // Make sure the lock is closed (no-op if it already closed itself).
    try? await receiver.cancelPairing()

    if paired == nil {
        if let code = pairError {
            print("No device paired (error 0x\(String(format: "%02X", code))).")
        } else {
            print("No device paired in time. Make sure the device is in pairing")
            print("mode and try `solcito pair` again.")
        }
    }
}

// MARK: - unpair

private func runUnpair(slot: UInt8) async {
    let manager = HIDManager()
    let receivers: [DiscoveredReceiver]
    do {
        receivers = try ReceiverDiscovery.find(using: manager)
    } catch {
        die("Couldn't scan for receivers. (\(error))")
    }
    guard !receivers.isEmpty else {
        die("No Logitech receiver found.")
    }
    let r = await chooseReceiver(from: receivers, prompt: "Which receiver has the device in slot \(slot)?")
    guard let hidpp = r.hidppInterface else {
        die("\(r.id.name) doesn't support unpairing.")
    }

    let device = HIDDevice(handle: hidpp)
    let receiver = Receiver(id: r.id, hidppDevice: device)
    defer { receiver.close() }
    do {
        try receiver.open()
    } catch {
        die("Couldn't open the receiver. Quit Logi Options+ or Logitech G Hub and try again.")
    }

    do {
        try await receiver.unpair(slot: slot)
        print("Removed the device in slot \(slot).")
    } catch {
        die("Couldn't unpair slot \(slot). (\(error))")
    }
}

// MARK: - helpers

private func chooseReceiver(from receivers: [DiscoveredReceiver], prompt: String) async -> DiscoveredReceiver {
    if receivers.count == 1 { return receivers[0] }

    write("Scanning receivers…")
    var counts: [Int?] = []
    for r in receivers {
        counts.append(await pairedCount(r))
    }
    write("\r\u{1B}[K")  // clear "Scanning…" line

    print("Multiple receivers found:")
    for (i, r) in receivers.enumerated() {
        print("  [\(i + 1)] \(r.id.name) \(summarize(count: counts[i]))")
    }
    print()

    while true {
        write("\(prompt) [1-\(receivers.count)]: ")
        guard let line = readLine() else {
            stderr("")
            die("No selection made.")
        }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(trimmed), (1...receivers.count).contains(n) {
            return receivers[n - 1]
        }
        print("Please enter a number between 1 and \(receivers.count).")
    }
}

private func pairedCount(_ r: DiscoveredReceiver) async -> Int? {
    guard let hidpp = r.hidppInterface else { return nil }
    let device = HIDDevice(handle: hidpp)
    let receiver = Receiver(id: r.id, hidppDevice: device)
    defer { receiver.close() }
    do {
        try receiver.open()
    } catch {
        return nil
    }
    let probes = await receiver.probeSlots()
    return probes.filter { $0.isPaired }.count
}

private func summarize(count: Int?) -> String {
    switch count {
    case nil:  return "(can't read)"
    case 0:    return "(empty)"
    case 1:    return "(1 device)"
    case let n?: return "(\(n) devices)"
    }
}

/// Writes to stdout without a newline and flushes — needed for prompts so
/// the cursor lands after the text rather than waiting for line buffering.
private func write(_ s: String) {
    FileHandle.standardOutput.write(Data(s.utf8))
}

private func stderr(_ msg: String) {
    FileHandle.standardError.write(Data("\(msg)\n".utf8))
}

private func die(_ msg: String) -> Never {
    stderr(msg)
    exit(1)
}
