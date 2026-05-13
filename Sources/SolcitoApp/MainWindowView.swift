import SwiftUI
import HIDPP

struct MainWindowView: View {
    @Environment(AppState.self) private var state
    @State private var showingPairSheet = false

    var body: some View {
        @Bindable var bState = state
        NavigationSplitView {
            sidebar
        } detail: {
            if let r = state.selectedReceiver {
                ReceiverDetailView(viewModel: r, showingPairSheet: $showingPairSheet)
            } else {
                ContentUnavailableView(
                    "No receiver selected",
                    systemImage: "computermouse",
                    description: Text("Plug in a Logitech receiver and click Refresh.")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button { state.refresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .navigationTitle("solcito")
    }

    private var sidebar: some View {
        @Bindable var bState = state
        return List(selection: $bState.selectedReceiverLocationID) {
            Section("Receivers") {
                if state.receivers.isEmpty {
                    Text("None detected").foregroundStyle(.secondary).italic()
                }
                ForEach(state.receivers) { r in
                    Label(r.discovered.id.name, systemImage: "dot.radiowaves.right")
                        .tag(r.locationID as UInt64?)
                }
            }
            if let err = state.lastError {
                Section("Error") {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct ReceiverDetailView: View {
    var viewModel: ReceiverViewModel
    @Binding var showingPairSheet: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Divider()

                Section {
                    InfoGrid(viewModel: viewModel)
                } header: {
                    Text("Receiver info").font(.headline)
                }

                Section {
                    DevicesList(viewModel: viewModel)
                } header: {
                    HStack {
                        Text("Paired devices").font(.headline)
                        Spacer()
                        Button("Pair new device…") { showingPairSheet = true }
                            .disabled(!viewModel.hasHIDPPInterface)
                    }
                }
            }
            .padding()
        }
        .task(id: viewModel.locationID) {
            await viewModel.loadInfo()
        }
        .sheet(isPresented: $showingPairSheet) {
            PairingSheet(viewModel: viewModel)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.discovered.id.name).font(.title2).fontWeight(.semibold)
            Text("\(viewModel.discovered.id.kind.displayName) — VID 0x\(String(format: "%04X", viewModel.discovered.id.vendorID)) PID 0x\(String(format: "%04X", viewModel.discovered.id.productID))")
                .foregroundStyle(.secondary)
        }
    }
}

private struct InfoGrid: View {
    var viewModel: ReceiverViewModel

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            row("Firmware", viewModel.info?.firmwareVersion ?? "—")
            row("Serial", viewModel.info?.serialNumber ?? "—")
            row("Max paired devices", viewModel.info?.maxPairedDevices.map(String.init) ?? "—")
            row("Currently connected", viewModel.info?.connectedDeviceCount.map(String.init) ?? "—")
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.isLoadingInfo { ProgressView().controlSize(.small) }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.leading)
            Text(value).font(.body.monospaced())
        }
    }
}

private struct DevicesList: View {
    var viewModel: ReceiverViewModel

    var body: some View {
        if viewModel.pairedDevices.isEmpty {
            Text("No paired devices responded to the ping.")
                .foregroundStyle(.secondary)
                .italic()
        } else {
            ForEach(viewModel.pairedDevices, id: \.slot) { d in
                HStack {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text("Slot \(d.slot)")
                    Spacer()
                    Text("HID++ \(d.hidppVersion)")
                        .foregroundStyle(.secondary)
                        .font(.body.monospaced())
                    Button(role: .destructive) {
                        Task { await viewModel.unpair(slot: d.slot) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Unpair slot \(d.slot)")
                }
                .padding(.vertical, 4)
            }
        }
    }
}
