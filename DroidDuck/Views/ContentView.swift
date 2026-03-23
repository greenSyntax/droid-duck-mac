import SwiftUI

// MARK: - ContentView

/// Root layout: sidebar (devices) + main content (file browser).
struct ContentView: View {

    @EnvironmentObject var deviceManager: DeviceManager
    @StateObject private var browserVM = FileBrowserViewModel()

    var body: some View {
        NavigationSplitView {
            DeviceSidebarView()
                .environmentObject(deviceManager)
                .environmentObject(browserVM)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            if let device = deviceManager.selectedDevice {
                FileBrowserView(device: device)
                    .environmentObject(browserVM)
                    .id(device.serial)   // force view rebuild on device switch
            } else {
                EmptyStateView()
                    .environmentObject(deviceManager)
            }
        }
        .frame(minWidth: 780, minHeight: 500)
        // When selected device changes, wire up the browser VM
        .onChange(of: deviceManager.selectedDevice) {
            if let device = deviceManager.selectedDevice {
                browserVM.attach(serial: device.serial)
            } else {
                browserVM.detach()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(DeviceManager())
}
