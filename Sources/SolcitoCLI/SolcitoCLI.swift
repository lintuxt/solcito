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
    print()
    print("  \(Tone.title("solcito"))  \(Tone.subtle("· Logitech wireless device manager for macOS"))")
    print()
    print("  \(Tone.muted("USAGE"))")
    let rows: [(String, String)] = [
        ("solcito",                "Show your receiver and the devices paired to it."),
        ("solcito pair",           "Add a new device. When prompted, turn the device off and on"),
        ("",                       "(or press its \"Connect\" button if it has one)."),
        ("solcito unpair <slot>",  "Remove the device in the given slot (1–6)."),
        ("solcito help",           "Show this help."),
    ]
    for (cmd, desc) in rows {
        let col = cmd.padding(toLength: 24, withPad: " ", startingAt: 0)
        print("    \(Tone.device(col))\(Tone.subtle(desc))")
    }
    print()
    print("  \(Tone.muted("TIP"))")
    print("    \(Tone.subtle("Most Logitech devices enter pairing mode when you switch them off"))")
    print("    \(Tone.subtle("and back on while a receiver's pairing window is open."))")
    print()
}

// MARK: - default: status

private func showStatus() async {
    printBanner()

    let manager = HIDManager()
    let receivers: [DiscoveredReceiver]
    do {
        receivers = try ReceiverDiscovery.find(using: manager)
    } catch {
        die(Tone.error("Couldn't scan for receivers. (\(error))"))
    }

    guard !receivers.isEmpty else {
        print("  \(Tone.warn("No Logitech receiver found."))")
        print("  \(Tone.subtle("Plug in your Logitech USB receiver, then run `solcito` again."))")
        print()
        return
    }

    let prefixed = receivers.count > 1
    for (index, r) in receivers.enumerated() {
        if index > 0 { print() }
        await printReceiverStatus(r, label: prefixed ? "[\(index + 1)]" : nil)
    }

    printCommandsFooter(multipleReceivers: prefixed)
}

private func printBanner() {
    print()
    print("  \(Tone.title("solcito"))  \(Tone.subtle("· Logitech wireless device manager"))")
    print()
}

private func printCommandsFooter(multipleReceivers: Bool) {
    print()
    print("  \(Tone.muted("Commands"))")
    let pairCol = "solcito pair".padding(toLength: 24, withPad: " ", startingAt: 0)
    let unpairCol = "solcito unpair <slot>".padding(toLength: 24, withPad: " ", startingAt: 0)
    let pairDesc = multipleReceivers ? "Pair a new device (you'll be asked which receiver)" : "Pair a new device"
    let unpairDesc = multipleReceivers ? "Remove a device (you'll be asked which receiver)" : "Remove a device"
    print("    \(pairCol)\(Tone.subtle(pairDesc))")
    print("    \(unpairCol)\(Tone.subtle(unpairDesc))")
    print()
}

private func printReceiverStatus(_ r: DiscoveredReceiver, label: String?) async {
    let labelPart = label.map { " \(Tone.muted($0))" } ?? ""
    print("  \(Icons.receiver)  \(Tone.receiver(r.id.name))\(labelPart)")

    guard let hidpp = r.hidppInterface else {
        print("      \(Tone.subtle("This receiver doesn't support pairing through solcito."))")
        return
    }

    let device = HIDDevice(handle: hidpp)
    let receiver = Receiver(id: r.id, hidppDevice: device)
    defer { receiver.close() }

    do {
        try receiver.open()
    } catch {
        print("      \(Tone.warn("Couldn't open the receiver."))")
        print("      \(Tone.subtle("Quit Logi Options+ or Logitech G Hub if running and try again."))")
        return
    }

    let probes = await receiver.probeSlots()
    let paired = probes.filter { $0.isPaired }
    if paired.isEmpty {
        print("      \(Tone.subtle("No paired devices"))")
        return
    }
    for p in paired {
        let details = await receiver.deviceDetails(slot: p.slot)
        let label = formatDeviceLabel(details)
        let slotTag = Tone.muted("· slot \(p.slot)")
        let suffix = (p.status == .silent) ? "  \(Tone.warn("(asleep)"))" : ""
        print("      \(icon(for: details.kind)) \(Tone.device(label))  \(slotTag)\(suffix)")
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
    let (r, receiver) = await chooseReceiver(from: receivers, prompt: "Which receiver should I pair to?")
    defer { receiver.close() }
    guard r.id.kind.supportsPairing else {
        die("\(r.id.name) can't pair new devices (this receiver type is fixed).")
    }

    let timeoutSeconds: UInt8 = 30
    print()
    print("  \(Icons.receiver)  \(Tone.receiver(r.id.name))")
    print("  \(Tone.subtle("Pairing window open for \(timeoutSeconds) seconds…"))")
    print("  \(Tone.heading("Turn your device off and back on now")) \(Tone.subtle("(or press its \"Connect\" button)"))")
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
        case .deviceConnected(let slot, let wpid, let kind):
            // The receiver sends two CONNECT_NOTIFs (discovered + authenticated).
            // The first one already has the right slot/kind/wpid; the receiver
            // also stores the device's marketing name and we can read that
            // back via register 0xB5 now that we know the slot.
            if paired == nil {
                paired = (slot, kind)
                let receiverName = await receiver.deviceDetails(slot: slot).name
                let details = DeviceDetails(slot: slot, name: receiverName, kind: kind, wpid: wpid)
                let label = formatDeviceLabel(details)
                let check = Tone.ok("✓")
                let slotTag = Tone.muted("slot \(slot)")
                print("  \(check) \(icon(for: kind)) \(Tone.device(label))  \(slotTag)")
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
            print("  \(Tone.error("✗ No device paired"))  \(Tone.subtle("(error 0x\(String(format: "%02X", code)))"))")
        } else {
            print("  \(Tone.warn("⌛ No device paired in time."))")
            print("  \(Tone.subtle("Make sure the device is in pairing mode and try `solcito pair` again."))")
        }
    }
    print()
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
    let (_, receiver) = await chooseReceiver(from: receivers, prompt: "Which receiver has the device in slot \(slot)?")
    defer { receiver.close() }

    do {
        try await receiver.unpair(slot: slot)
        print()
        print("  \(Tone.ok("✓")) Removed the device in \(Tone.device("slot \(slot)")).")
        print()
    } catch {
        die(Tone.error("Couldn't unpair slot \(slot). (\(error))"))
    }
}

// MARK: - helpers

/// Opens every receiver, probes them concurrently (sequentially per
/// receiver so a single dispatcher serves each one), and lets the user pick
/// one. The chosen receiver is returned still open; the others are closed.
///
/// We open each `IOHIDDevice` exactly once because IOKit's HID stack
/// doesn't allow a fresh open after IOHIDDeviceCancel has torn down the
/// dispatch queue — re-opening within the same process trace-traps.
private func chooseReceiver(from receivers: [DiscoveredReceiver], prompt: String) async -> (DiscoveredReceiver, Receiver) {
    // Open each receiver up-front. Skips ones without a HID++ interface or
    // that we can't talk to (Logi Options+ holding exclusive access, etc.).
    var opened: [(meta: DiscoveredReceiver, receiver: Receiver?, count: Int?)] = []
    if receivers.count > 1 { write("Scanning receivers…") }
    for r in receivers {
        guard let hidpp = r.hidppInterface else {
            opened.append((r, nil, nil)); continue
        }
        let device = HIDDevice(handle: hidpp)
        let receiver = Receiver(id: r.id, hidppDevice: device)
        do {
            try receiver.open()
        } catch {
            opened.append((r, nil, nil)); continue
        }
        let probes = await receiver.probeSlots()
        let count = probes.filter { $0.isPaired }.count
        opened.append((r, receiver, count))
    }
    if receivers.count > 1 { write("\r\u{1B}[K") }

    let pickIndex: Int
    if opened.count == 1 {
        pickIndex = 0
    } else {
        print()
        print("  \(Tone.heading("Multiple receivers found:"))")
        for (i, item) in opened.enumerated() {
            let tag = Tone.muted("[\(i + 1)]")
            let info = Tone.subtle(summarize(count: item.count))
            print("    \(tag) \(Icons.receiver)  \(Tone.receiver(item.meta.id.name))  \(info)")
        }
        print()
        pickIndex = readChoice(prompt: prompt, range: 1...opened.count, opened: opened) - 1
    }

    // Close every receiver except the chosen one.
    for (i, item) in opened.enumerated() where i != pickIndex {
        item.receiver?.close()
    }

    guard let receiver = opened[pickIndex].receiver else {
        die("Couldn't open \(opened[pickIndex].meta.id.name). Quit Logi Options+ or Logitech G Hub and try again.")
    }
    return (opened[pickIndex].meta, receiver)
}

private func readChoice(
    prompt: String,
    range: ClosedRange<Int>,
    opened: [(meta: DiscoveredReceiver, receiver: Receiver?, count: Int?)]
) -> Int {
    while true {
        write("\(prompt) [\(range.lowerBound)-\(range.upperBound)]: ")
        guard let line = readLine() else {
            for item in opened { item.receiver?.close() }
            stderr("")
            die("No selection made.")
        }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(trimmed), range.contains(n) { return n }
        print("Please enter a number between \(range.lowerBound) and \(range.upperBound).")
    }
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
