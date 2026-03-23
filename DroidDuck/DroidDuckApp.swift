import SwiftUI

@main
struct DroidDuckApp: App {

    @StateObject private var deviceManager = DeviceManager()
    @State private var showDiagnostics = false
    @State private var showAbout = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deviceManager)
                .onAppear {
                    deviceManager.start()
                }
                .onDisappear {
                    deviceManager.stop()
                }
                .sheet(isPresented: $showDiagnostics) {
                    DiagnosticsView()
                }
                .sheet(isPresented: $showAbout) {
                    AboutView()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // Replace the default "About DroidDuck" item with our custom one
            CommandGroup(replacing: .appInfo) {
                Button("About DroidDuck") {
                    showAbout = true
                }
            }

            // Hide "New Window"
            CommandGroup(replacing: .newItem) { }

            // Device menu
            CommandMenu("Device") {
                Button("Refresh Devices") {
                    deviceManager.manualRefresh()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            // Help menu — append Diagnostics item
            CommandGroup(after: .help) {
                Button("Diagnostics") {
                    showDiagnostics = true
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
            }
        }
    }
}
