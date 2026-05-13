import SwiftUI

struct PairingSheet: View {
    var viewModel: ReceiverViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var timeout: Double = 30
    @State private var pairingTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pair a new device").font(.title3).fontWeight(.semibold)
            Text("Press the pair button on the Logitech device while the lock is open. Most devices need a tap on the small \"connect\" button under the device.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Timeout")
                Slider(value: $timeout, in: 5...60, step: 5)
                Text("\(Int(timeout))s").font(.body.monospaced()).frame(width: 38, alignment: .trailing)
            }
            .disabled(viewModel.isPairing)

            GroupBox("Events") {
                if viewModel.pairingLog.isEmpty {
                    Text("Waiting for pairing to start…")
                        .foregroundStyle(.secondary).italic()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(viewModel.pairingLog.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.body.monospaced())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                }
            }

            HStack {
                if viewModel.isPairing {
                    ProgressView().controlSize(.small)
                    Text("Pairing window open…").foregroundStyle(.secondary)
                }
                Spacer()
                Button(viewModel.isPairing ? "Close" : "Cancel") {
                    pairingTask?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Start pairing") {
                    pairingTask = Task { await viewModel.startPairing(timeoutSeconds: UInt8(timeout)) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isPairing)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
