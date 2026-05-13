import SwiftUI

@main
struct SolcitoApp: App {
    @State private var state = AppState()

    var body: some Scene {
        Window("solcito", id: "main") {
            MainWindowView()
                .environment(state)
                .frame(minWidth: 640, minHeight: 420)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}  // there's no "new document"
            CommandGroup(after: .appInfo) {
                Button("Refresh receivers") { state.refresh() }
                    .keyboardShortcut("r")
            }
        }

        MenuBarExtra("solcito", systemImage: "computermouse") {
            MenuBarContentView()
                .environment(state)
        }
        .menuBarExtraStyle(.window)
    }
}
