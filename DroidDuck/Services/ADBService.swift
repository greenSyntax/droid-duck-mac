import Foundation

// MARK: - ADB Errors

enum ADBError: LocalizedError {
    case adbNotFound
    case homebrewNotFound
    case commandFailed(String)
    case parseError(String)
    case noDeviceSelected

    var errorDescription: String? {
        switch self {
        case .adbNotFound:
            return "ADB (Android Debug Bridge) was not found on your system."
        case .homebrewNotFound:
            return "Homebrew is not installed. Visit https://brew.sh to install it, then try again."
        case .commandFailed(let msg):
            return "ADB command failed: \(msg)"
        case .parseError(let msg):
            return "Failed to parse ADB output: \(msg)"
        case .noDeviceSelected:
            return "No Android device selected."
        }
    }
}

// MARK: - ADBService

/// Core service that wraps ADB shell commands.
/// Marked as an `actor` so all async ADB calls are serialised safely.
actor ADBService {

    static let shared = ADBService()

    private(set) var adbPath: String = ""
    private(set) var isReady: Bool = false

    // MARK: - Initialisation

    /// Call once at app startup to locate ADB and start its daemon.
    func bootstrap() async throws {
        adbPath = try await resolveADBPath()
        try await startServer()
        isReady = true
    }

    // MARK: - ADB Discovery

    private func resolveADBPath() async throws -> String {
        let candidates: [String] = [
            // Homebrew (Apple Silicon)
            "/opt/homebrew/bin/adb",
            // Homebrew (Intel)
            "/usr/local/bin/adb",
            // Android Studio default SDK location
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            // Manual SDK install (common alternative)
            "\(NSHomeDirectory())/Android/sdk/platform-tools/adb",
            // System-wide
            "/usr/bin/adb",
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Ask `which` — covers any custom PATH additions (e.g. ~/.zshrc exports).
        // NOTE: Process requires a full absolute path; we can never fall back to
        // the bare string "adb" — that causes "The file doesn't exist" at runtime.
        let whichResult = try? await runRaw(executable: "/usr/bin/which", args: ["adb"])
        let whichPath = whichResult?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !whichPath.isEmpty, FileManager.default.fileExists(atPath: whichPath) {
            return whichPath
        }

        throw ADBError.adbNotFound
    }

    /// Returns the resolved ADB path without throwing — useful for diagnostics.
    func resolvedADBPathOrNil() async -> String? {
        return try? await resolveADBPath()
    }

    /// Returns the output of `adb version` — useful for diagnostics.
    func adbVersion() async -> String {
        guard isReady else { return "ADB not ready" }
        let result = try? await runRaw(executable: adbPath, args: ["version"])
        return result?.output
            .components(separatedBy: "\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Unknown"
    }

    // MARK: - Process Runner

    struct ProcessResult {
        let output: String
        let error: String
        let exitCode: Int32

        var succeeded: Bool { exitCode == 0 }
        var combinedOutput: String {
            [output, error].filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    /// Low-level process runner — use `run(_:)` or `run(serial:_:)` instead.
    func runRaw(executable: String, args: [String], timeoutSeconds: Double = 30) async throws -> ProcessResult {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Ensure clean PATH so ADB can find its own helpers
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
            process.environment = env

            process.terminationHandler = { proc in
                let out  = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err  = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: ProcessResult(output: out, error: err, exitCode: proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Convenience ADB Runners

    /// Run an ADB command (no specific device).
    @discardableResult
    func run(_ args: [String]) async throws -> String {
        let result = try await runRaw(executable: adbPath, args: args)
        return result.output
    }

    /// Run an ADB command targeting a specific device serial.
    @discardableResult
    func run(serial: String, _ args: [String]) async throws -> String {
        let result = try await runRaw(executable: adbPath, args: ["-s", serial] + args)
        return result.output
    }

    // MARK: - Server

    func startServer() async throws {
        _ = try? await run(["start-server"])
    }

    func killServer() async throws {
        _ = try? await run(["kill-server"])
    }

    // MARK: - Device Enumeration

    /// Returns all currently connected devices (any status).
    func listDevices() async throws -> [DeviceInfo] {
        let output = try await run(["devices"])
        var devices: [DeviceInfo] = []

        for line in output.components(separatedBy: "\n") {
            if let device = DeviceInfo.from(adbDevicesLine: line) {
                devices.append(device)
            }
        }

        // Enrich with model names concurrently
        await withTaskGroup(of: (Int, String?).self) { group in
            for (idx, device) in devices.enumerated() where device.status == .device {
                group.addTask {
                    let model = try? await self.fetchModel(serial: device.serial)
                    return (idx, model)
                }
            }
            for await (idx, model) in group {
                devices[idx].model = model
            }
        }

        return devices
    }

    /// Fetch `ro.product.model` for a device.
    func fetchModel(serial: String) async throws -> String {
        let raw = try await run(serial: serial, ["shell", "getprop", "ro.product.model"])
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - File System

    /// List directory contents. Returns parsed FileNode array sorted: dirs first, then files.
    func listDirectory(serial: String, path: String) async throws -> [FileNode] {
        // Use `ls -la` for detailed listing.
        // `--color=never` prevents ANSI escape codes on some Android builds.
        let output = try await run(serial: serial, ["shell", "ls", "-la", "--color=never", escapedPath(path)])
        var nodes: [FileNode] = []

        for line in output.components(separatedBy: "\n") {
            if let node = FileNode.from(lsLine: line, parentPath: path) {
                nodes.append(node)
            }
        }

        // Sort: directories first, then alphabetically (case-insensitive)
        return nodes.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Check whether a path is accessible on the device.
    func pathExists(serial: String, path: String) async throws -> Bool {
        let result = try await runRaw(executable: adbPath,
                                      args: ["-s", serial, "shell", "test", "-e", escapedPath(path), "&&", "echo", "YES"])
        return result.output.contains("YES")
    }

    // MARK: - Homebrew ADB Installer

    /// Locate the Homebrew binary.
    func findHomebrew() -> String? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Install `android-platform-tools` via Homebrew, streaming each output line
    /// back to the caller via the `onOutput` closure (called on a background thread).
    ///
    /// - Parameter onOutput: Called for every new line of stdout/stderr from brew.
    /// - Throws: `ADBError.adbNotFound` if Homebrew itself isn't installed.
    func installViaHomebrew(onOutput: @escaping (String) -> Void) async throws {
        guard let brew = findHomebrew() else {
            throw ADBError.homebrewNotFound
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: brew)
        process.arguments = ["install", "--cask", "android-platform-tools"]
        process.standardOutput = stdoutPipe
        process.standardError  = stderrPipe

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"   // skip brew self-update for speed
        process.environment = env

        // Stream stdout line by line
        let stdoutHandle = stdoutPipe.fileHandleForReading
        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                for line in text.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { onOutput(trimmed) }
                }
            }
        }

        // Stream stderr line by line (brew writes progress here)
        let stderrHandle = stderrPipe.fileHandleForReading
        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                for line in text.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { onOutput(trimmed) }
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil

                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ADBError.commandFailed("brew exited with code \(proc.terminationStatus)"))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - File Transfer

    /// Pull a single file from the device to a local temp directory.
    /// Returns the local `URL` where the file was saved.
    func pullFile(serial: String, remotePath: String) async throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DroidDuck", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let fileName = URL(fileURLWithPath: remotePath).lastPathComponent
        // Append a short hash to avoid collisions when two files share the same name
        let localURL  = tempDir.appendingPathComponent("\(remotePath.hashValue)_\(fileName)")

        // Remove any stale copy first
        try? FileManager.default.removeItem(at: localURL)

        let result = try await runRaw(
            executable: adbPath,
            args: ["-s", serial, "pull", remotePath, localURL.path],
            timeoutSeconds: 60
        )

        guard FileManager.default.fileExists(atPath: localURL.path) else {
            let msg = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ADBError.commandFailed(msg.isEmpty ? "adb pull returned no output" : msg)
        }

        return localURL
    }

    // MARK: - Search

    /// Search for files/folders whose name matches `query` (case-insensitive),
    /// starting from `inPath`, up to `maxDepth` levels deep.
    ///
    /// Returns a tuple array of `(path, isDirectory)` sorted: directories first.
    func searchFiles(
        serial: String,
        inPath: String,
        query: String,
        maxDepth: Int = 10
    ) async throws -> [(path: String, isDirectory: Bool)] {

        // Sanitise query — strip characters that could break the shell glob
        let safeQuery = query
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: ";", with: "")
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "&", with: "")

        guard !safeQuery.isEmpty else { return [] }

        // Run two find passes in parallel: one for files, one for dirs.
        // BusyBox find (standard on Android) supports -type f/-type d.
        // Pipe through head -300 to cap results.
        let basePath = escapedPath(inPath)
        let pattern  = "'*\(safeQuery)*'"

        async let fileOutput = run(serial: serial, [
            "shell",
            "find \(basePath) -maxdepth \(maxDepth) -iname \(pattern) -type f 2>/dev/null | head -200"
        ])
        async let dirOutput = run(serial: serial, [
            "shell",
            "find \(basePath) -maxdepth \(maxDepth) -iname \(pattern) -type d 2>/dev/null | head -100"
        ])

        let (files, dirs) = try await (fileOutput, dirOutput)

        func parsePaths(_ raw: String, isDirectory: Bool) -> [(path: String, isDirectory: Bool)] {
            raw.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("find:") && $0.hasPrefix("/") }
                .map { (path: $0, isDirectory: isDirectory) }
        }

        // Dirs first, then files — both alphabetically sorted
        let dirResults  = parsePaths(dirs,  isDirectory: true ).sorted  { $0.path < $1.path }
        let fileResults = parsePaths(files, isDirectory: false).sorted  { $0.path < $1.path }
        return dirResults + fileResults
    }

    // MARK: - Helpers

    /// Wrap a path in single quotes so spaces are handled correctly by the shell.
    private func escapedPath(_ path: String) -> String {
        // Escape any existing single quotes in the path first
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
