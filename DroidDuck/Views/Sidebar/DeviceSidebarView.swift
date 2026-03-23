import SwiftUI

// MARK: - StorageLocation

/// A named shortcut to a common Android storage path.
struct StorageLocation: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let icon: String
    let color: Color

    // Common Android locations
    static let internalStorage = StorageLocation(name: "Internal Storage", path: "/sdcard",                        icon: "internaldrive.fill",       color: .accentColor)
    static let downloads       = StorageLocation(name: "Downloads",        path: "/sdcard/Download",              icon: "arrow.down.circle.fill",   color: .blue)
    static let camera          = StorageLocation(name: "Camera",           path: "/sdcard/DCIM/Camera",           icon: "camera.fill",              color: .yellow)
    static let pictures        = StorageLocation(name: "Pictures",         path: "/sdcard/Pictures",              icon: "photo.fill",               color: .pink)
    static let music           = StorageLocation(name: "Music",            path: "/sdcard/Music",                 icon: "music.note",               color: .mint)
    static let movies          = StorageLocation(name: "Movies",           path: "/sdcard/Movies",                icon: "film.fill",                color: .orange)
    static let documents       = StorageLocation(name: "Documents",        path: "/sdcard/Documents",             icon: "doc.fill",                 color: .brown)
    static let whatsApp        = StorageLocation(name: "WhatsApp",         path: "/sdcard/Android/media/com.whatsapp/WhatsApp/Media", icon: "message.fill", color: .green)
    static let androidData     = StorageLocation(name: "Android",          path: "/sdcard/Android",               icon: "folder.badge.gearshape",   color: .secondary)
    static let root            = StorageLocation(name: "Root  /",          path: "/",                             icon: "externaldrive.fill",       color: .secondary)

    static let all: [StorageLocation] = [
        .internalStorage, .downloads, .camera, .pictures,
        .music, .movies, .documents, .whatsApp, .androidData, .root
    ]
}

// MARK: - DeviceSidebarView

struct DeviceSidebarView: View {

    @EnvironmentObject var deviceManager: DeviceManager
    @EnvironmentObject var browserVM: FileBrowserViewModel

    var body: some View {
        List {
            // ── Devices section ──────────────────────────────
            Section {
                if !deviceManager.adbReady {
                    adbNotReadyRow
                } else if deviceManager.isLoading && deviceManager.devices.isEmpty {
                    loadingRow
                } else if deviceManager.devices.isEmpty {
                    noDevicesRow
                } else {
                    ForEach(deviceManager.devices) { device in
                        DeviceRowView(device: device)
                            .tag(device)
                            .onTapGesture { deviceManager.select(device) }
                            .listRowBackground(
                                deviceManager.selectedDevice?.serial == device.serial
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear
                            )
                    }
                }
            } header: {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .imageScale(.small)
                    Text("Devices")
                    Spacer()
                    Button { deviceManager.manualRefresh() } label: {
                        Image(systemName: "arrow.clockwise").imageScale(.small)
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh  ⌘⇧R")
                }
            }

            // ── Locations section ─────────────────────────────
            if deviceManager.selectedDevice?.status == .device {
                Section("Locations") {
                    ForEach(StorageLocation.all) { location in
                        LocationRowView(
                            location: location,
                            isActive: browserVM.currentPath == location.path
                        )
                        .onTapGesture { browserVM.navigate(toPath: location.path) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let error = deviceManager.errorMessage {
                errorBanner(message: error)
            }
        }
    }

    // MARK: - State rows

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text("Scanning…").font(.caption).foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
    }

    private var noDevicesRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("No devices found", systemImage: "phone.slash")
                .font(.callout).foregroundStyle(.secondary)
            Text("Connect via USB and enable\nUSB Debugging on your phone.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .listRowBackground(Color.clear)
    }

    private var adbNotReadyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("ADB not found", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
            Text("Install: brew install --cask\nandroid-platform-tools")
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .listRowBackground(Color.clear)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            Text(message).font(.caption).lineLimit(2)
        }
        .padding(8)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(8)
    }
}

// MARK: - LocationRowView

struct LocationRowView: View {
    let location: StorageLocation
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: location.icon)
                .imageScale(.small)
                .foregroundStyle(isActive ? Color.white : location.color)
                .frame(width: 18)

            Text(location.name)
                .font(.callout)
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(
            isActive
                ? RoundedRectangle(cornerRadius: 5).fill(Color.accentColor)
                : RoundedRectangle(cornerRadius: 5).fill(Color.clear)
        )
        .contentShape(Rectangle())
        .help(location.path)
    }
}

// MARK: - DeviceRowView

struct DeviceRowView: View {

    let device: DeviceInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "iphone")
                .imageScale(.large)
                .foregroundStyle(device.status.isBrowsable ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(device.status.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(device.status.isBrowsable ? 1 : 0.6)
    }

    private var statusColor: Color {
        switch device.status {
        case .device:       return .green
        case .unauthorized: return .orange
        case .offline:      return .red
        case .recovery:     return .yellow
        case .unknown:      return .gray
        }
    }
}
