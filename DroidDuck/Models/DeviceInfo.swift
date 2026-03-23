import Foundation

// MARK: - DeviceInfo
/// Represents a connected Android device discovered via ADB.
struct DeviceInfo: Identifiable, Hashable, Equatable {

    /// The ADB serial number — used as the stable identifier.
    var id: String { serial }

    let serial: String
    let status: DeviceStatus

    /// Human-readable model name fetched from `adb shell getprop ro.product.model`.
    var model: String?

    /// Friendly display name: model if available, otherwise the serial.
    var displayName: String { model ?? serial }

    // MARK: - Status

    enum DeviceStatus: String, Hashable {
        case device        = "device"       // fully authorised & connected
        case unauthorized  = "unauthorized" // waiting for user to accept RSA prompt
        case offline       = "offline"      // USB connected but ADB not responding
        case recovery      = "recovery"     // device in recovery mode
        case unknown

        var label: String {
            switch self {
            case .device:       return "Connected"
            case .unauthorized: return "Unauthorized"
            case .offline:      return "Offline"
            case .recovery:     return "Recovery"
            case .unknown:      return "Unknown"
            }
        }

        var systemImage: String {
            switch self {
            case .device:       return "checkmark.circle.fill"
            case .unauthorized: return "lock.circle.fill"
            case .offline:      return "xmark.circle.fill"
            case .recovery:     return "exclamationmark.circle.fill"
            case .unknown:      return "questionmark.circle.fill"
            }
        }

        /// Whether the user can actually browse files on this device.
        var isBrowsable: Bool { self == .device }

        init(rawString: String) {
            self = DeviceStatus(rawValue: rawString) ?? .unknown
        }
    }

    // MARK: - Parsing

    /// Parse a single line from `adb devices` output.
    /// Format:  `<serial>\t<status>`
    static func from(adbDevicesLine line: String) -> DeviceInfo? {
        let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let serial = parts[0].trimmingCharacters(in: .whitespaces)
        let status = parts[1].trimmingCharacters(in: .whitespaces)
        guard !serial.isEmpty, serial != "List of devices attached" else { return nil }
        return DeviceInfo(serial: serial, status: DeviceStatus(rawString: status))
    }
}
