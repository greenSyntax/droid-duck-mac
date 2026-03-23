import SwiftUI

// MARK: - DiagnosticsViewModel

@MainActor
final class DiagnosticsViewModel: ObservableObject {

    struct DiagRow: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let status: Status

        enum Status { case ok, warn, fail, neutral }
    }

    @Published var rows: [DiagRow] = []
    @Published var isRunning = false

    func run() {
        Task { await collect() }
    }

    private func collect() async {
        isRunning = true
        rows = []

        // 1. macOS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        append("macOS", osVersion, .neutral)

        // 2. App sandbox
        let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
        append("App Sandbox",
               sandboxed ? "Enabled (ADB subprocess may be blocked)" : "Disabled ✓",
               sandboxed ? .warn : .ok)

        // 3. Homebrew
        let brewPath = await ADBService.shared.findHomebrew()
        append("Homebrew",
               brewPath ?? "Not found — visit https://brew.sh",
               brewPath != nil ? .ok : .fail)

        // 4. ADB binary
        let adbPath = await ADBService.shared.resolvedADBPathOrNil()
        append("ADB binary",
               adbPath ?? "Not found",
               adbPath != nil ? .ok : .fail)

        // 5. ADB version
        let adbVer = await ADBService.shared.adbVersion()
        append("ADB version", adbVer, adbPath != nil ? .ok : .neutral)

        // 6. ADB server / daemon
        let serverRunning: Bool
        if let path = adbPath {
            let result = try? await ADBService.shared.runRaw(executable: path, args: ["get-state"])
            serverRunning = result?.output.trimmingCharacters(in: .whitespacesAndNewlines) == "host"
                         || result?.exitCode == 0
        } else {
            serverRunning = false
        }
        append("ADB daemon",
               serverRunning ? "Running" : (adbPath != nil ? "Not running (will start on use)" : "N/A"),
               adbPath != nil ? .ok : .neutral)

        // 7. Connected devices
        let devices = (try? await ADBService.shared.listDevices()) ?? []
        let devSummary: String
        let devStatus: DiagRow.Status
        if devices.isEmpty {
            devSummary = "None detected"
            devStatus = .warn
        } else {
            let authorised = devices.filter { $0.status == .device }.count
            let unauth     = devices.filter { $0.status == .unauthorized }.count
            var parts: [String] = []
            if authorised > 0 { parts.append("\(authorised) connected") }
            if unauth > 0     { parts.append("\(unauth) unauthorized") }
            devSummary = parts.joined(separator: ", ")
            devStatus  = authorised > 0 ? .ok : .warn
        }
        append("Devices", devSummary, devStatus)

        // 8. Common ADB paths checked
        let commonPaths = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
        ]
        for p in commonPaths {
            let exists = FileManager.default.fileExists(atPath: p)
            append("  \(p)", exists ? "Found ✓" : "—", exists ? .ok : .neutral)
        }

        isRunning = false
    }

    private func append(_ label: String, _ value: String, _ status: DiagRow.Status) {
        rows.append(DiagRow(label: label, value: value, status: status))
    }
}

// MARK: - DiagnosticsView

struct DiagnosticsView: View {

    @StateObject private var vm = DiagnosticsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "stethoscope")
                    .foregroundStyle(Color.accentColor)
                Text("Diagnostics")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Results table
            if vm.isRunning && vm.rows.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Running diagnostics…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(vm.rows) { row in
                            DiagRowView(row: row)
                            Divider().padding(.leading, 16)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Divider()

            // Footer
            HStack {
                if vm.isRunning {
                    ProgressView().scaleEffect(0.7)
                    Text("Running…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Run Again") { vm.run() }
                    .disabled(vm.isRunning)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 520, height: 420)
        .onAppear { vm.run() }
    }
}

// MARK: - DiagRowView

private struct DiagRowView: View {
    let row: DiagnosticsViewModel.DiagRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Status dot
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            // Label
            Text(row.label)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 200, alignment: .leading)
                .lineLimit(1)

            // Value
            Text(row.value)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private var dotColor: Color {
        switch row.status {
        case .ok:      return .green
        case .warn:    return .orange
        case .fail:    return .red
        case .neutral: return Color(NSColor.tertiaryLabelColor)
        }
    }
}
