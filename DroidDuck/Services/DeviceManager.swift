import Foundation
import Combine

// MARK: - DeviceManager

/// Observable object that keeps track of connected ADB devices.
/// Polls `adb devices` every `pollInterval` seconds.
@MainActor
final class DeviceManager: ObservableObject {

    // MARK: - Install State

    enum InstallState: Equatable {
        case idle
        case installing
        case succeeded
        case failed(String)
    }

    // MARK: - Published State

    @Published var devices: [DeviceInfo] = []
    @Published var selectedDevice: DeviceInfo? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var adbReady: Bool = false

    @Published var installState: InstallState = .idle
    @Published var installLog: [String] = []
    @Published var hasHomebrew: Bool = false

    // MARK: - Config

    let pollInterval: TimeInterval = 3.0  // seconds between `adb devices` polls

    // MARK: - Private

    private var pollTask: Task<Void, Never>? = nil

    // MARK: - Lifecycle

    /// Bootstrap ADB and start polling.
    func start() {
        Task {
            await bootstrap()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        isLoading = true
        errorMessage = nil
        hasHomebrew = await ADBService.shared.findHomebrew() != nil
        do {
            try await ADBService.shared.bootstrap()
            adbReady = true
            await refresh()
            startPolling()
        } catch let error as ADBError {
            errorMessage = error.errorDescription
            adbReady = false
        } catch {
            errorMessage = error.localizedDescription
            adbReady = false
        }
        isLoading = false
    }

    // MARK: - ADB Auto-Install

    /// Run `brew install --cask android-platform-tools`, stream output into `installLog`,
    /// then re-bootstrap ADB when done.
    func installADB() {
        guard installState != .installing else { return }
        installLog = []
        installState = .installing

        Task {
            do {
                try await ADBService.shared.installViaHomebrew { [weak self] line in
                    Task { @MainActor [weak self] in
                        self?.installLog.append(line)
                    }
                }
                installLog.append("✅ Installation complete. Starting ADB…")
                installState = .succeeded
                // Re-run bootstrap so the app picks up the freshly installed ADB
                await bootstrap()
            } catch {
                installLog.append("❌ \(error.localizedDescription)")
                installState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.pollInterval ?? 3.0) * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
    }

    // MARK: - Refresh

    /// Manually trigger a device scan.
    func refresh() async {
        guard adbReady else { return }
        do {
            let fresh = try await ADBService.shared.listDevices()
            reconcile(newDevices: fresh)
        } catch {
            // Silently swallow poll errors; surface only to user on explicit refresh
        }
    }

    /// Force-refresh and surface errors to the user.
    func manualRefresh() {
        Task {
            isLoading = true
            errorMessage = nil
            do {
                let fresh = try await ADBService.shared.listDevices()
                reconcile(newDevices: fresh)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    // MARK: - Reconciliation

    /// Merge newly discovered devices into the published list without
    /// losing the currently selected device if it's still connected.
    private func reconcile(newDevices: [DeviceInfo]) {
        devices = newDevices

        // If selected device has disappeared or become unauthorised, deselect.
        if let selected = selectedDevice {
            let stillPresent = newDevices.first(where: { $0.serial == selected.serial })
            if let updated = stillPresent {
                selectedDevice = updated   // update with latest status / model
            } else {
                selectedDevice = nil
            }
        }

        // Auto-select if exactly one authorised device connected and nothing selected.
        if selectedDevice == nil,
           let only = newDevices.first(where: { $0.status == .device }),
           newDevices.filter({ $0.status == .device }).count == 1 {
            selectedDevice = only
        }
    }

    // MARK: - Selection

    func select(_ device: DeviceInfo) {
        guard device.status.isBrowsable else { return }
        selectedDevice = device
    }

    func deselect() {
        selectedDevice = nil
    }
}
