import SwiftUI

struct MenuBarContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("solcito").font(.headline)

            if state.receivers.isEmpty {
                Text("No receivers detected").foregroundStyle(.secondary)
            } else {
                ForEach(state.receivers) { r in
                    HStack {
                        Image(systemName: r.hasHIDPPInterface ? "dot.radiowaves.right" : "exclamationmark.triangle")
                        VStack(alignment: .leading) {
                            Text(r.discovered.id.name).font(.body)
                            if let fw = r.info?.firmwareVersion {
                                Text("Firmware \(fw)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Open main window") { openWindow(id: "main") }
            Button("Refresh") { state.refresh() }
            Divider()
            Button("Quit solcito") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 240)
    }
}
