import SwiftUI

// MARK: - EmptyStateView
/// Shown in the detail pane when no device is selected.
struct EmptyStateView: View {

    @EnvironmentObject var deviceManager: DeviceManager

    var body: some View {
        VStack(spacing: 20) {
            // Duck icon
            ZStack {
                Image("img_android")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
            }

            VStack(spacing: 6) {
                Text("DroidDuck")
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            // State-dependent content
            if !deviceManager.adbReady {
                adbSetupView
            } else if deviceManager.devices.isEmpty {
                connectHintView
            } else {
                selectDeviceView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Subtitle

    private var subtitle: String {
        if !deviceManager.adbReady {
            return "ADB is required to communicate with your Android device."
        } else if deviceManager.devices.isEmpty {
            return "No Android devices detected yet.\nConnect a device and enable USB Debugging."
        } else {
            return "Select a device from the sidebar to start exploring its files."
        }
    }

    // MARK: - ADB not found view

    @ViewBuilder
    private var adbSetupView: some View {
        switch deviceManager.installState {
        case .idle, .failed:
            idleInstallView

        case .installing:
            installingView

        case .succeeded:
            // Bootstrap re-runs after install; this state is transient
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
                Text("ADB installed! Connecting…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var idleInstallView: some View {
        VStack(spacing: 14) {
            if deviceManager.hasHomebrew {
                // Homebrew found — offer one-click install
                VStack(spacing: 6) {
                    Text("Homebrew detected on your Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("DroidDuck can install Android Platform Tools automatically.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    deviceManager.installADB()
                } label: {
                    Label("Install ADB Automatically", systemImage: "arrow.down.circle.fill")
                        .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                // Show error from previous failed attempt
                if case .failed(let msg) = deviceManager.installState {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
            } else {
                // No Homebrew — show manual instructions
                VStack(spacing: 10) {
                    Text("Install Homebrew first:")
                        .font(.subheadline)
                    Text("/bin/bash -c \"$(curl -fsSL https://brew.sh/install.sh)\"")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)

                    Text("Then install ADB:")
                        .font(.subheadline)
                    Text("brew install --cask android-platform-tools")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)

                    Button("Retry Detection") {
                        deviceManager.manualRefresh()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var installingView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Installing Android Platform Tools…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Live scrolling log
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(deviceManager.installLog.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(8)
                }
                .frame(width: 400, height: 160)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: deviceManager.installLog.count) { _ in
                    if let last = deviceManager.installLog.indices.last {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }
    }

    // MARK: - Device hints

    private var connectHintView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Enable USB Debugging on your phone", systemImage: "ladybug.fill")
                .font(.callout).foregroundStyle(.secondary)
            Label("Use a data-capable USB cable", systemImage: "cable.connector")
                .font(.callout).foregroundStyle(.secondary)
            Label("Accept the RSA key prompt on your phone", systemImage: "key.fill")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var selectDeviceView: some View {
        Label("\(deviceManager.devices.count) device(s) listed in the sidebar", systemImage: "arrow.left")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
