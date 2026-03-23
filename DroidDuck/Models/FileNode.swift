import Foundation

// MARK: - FileNode
/// Represents a single file or directory entry on the Android device.
struct FileNode: Identifiable, Hashable {

    let id = UUID()

    let name: String
    let path: String          // full absolute path on device
    let type: FileType
    let permissions: String?  // e.g. "drwxrwx--x"
    let owner: String?
    let group: String?
    let size: Int64?          // bytes (nil for directories in most Android ls output)
    let modifiedDate: String? // raw string from ls; e.g. "2024-03-01 10:23"
    let symlinkTarget: String? // only set when type == .symlink

    // MARK: - File Type

    enum FileType: Hashable {
        case directory
        case file
        case symlink
        case unknown
    }

    var isDirectory: Bool { type == .directory || (type == .symlink) }

    // MARK: - System file detection

    /// Well-known Android OS paths that belong to the system and should not be modified.
    private static let systemPrefixes: [String] = [
        "/system", "/vendor", "/apex", "/proc", "/dev", "/sys",
        "/sbin", "/bin", "/etc", "/lib", "/lib64", "/oem",
        "/firmware", "/boot", "/recovery", "/acct", "/d",
        "/debug_ramdisk", "/linkerconfig", "/metadata", "/postinstall"
    ]

    /// True when this entry lives inside a known Android system directory.
    var isSystemEntry: Bool {
        FileNode.systemPrefixes.contains(where: {
            path == $0 || path.hasPrefix($0 + "/")
        })
    }

    /// True when the permissions string has no write bits set for anyone.
    var isReadOnly: Bool {
        guard let perms = permissions, perms.count >= 10 else { return false }
        let indices = [2, 5, 8] // owner-w, group-w, other-w positions
        return indices.allSatisfy { i in
            let idx = perms.index(perms.startIndex, offsetBy: i)
            return perms[idx] != "w"
        }
    }

    // MARK: - Derived helpers

    var fileExtension: String {
        guard type == .file else { return "" }
        return (name as NSString).pathExtension.lowercased()
    }

    /// True when the file is a previewable image format.
    var isImageFile: Bool {
        guard type == .file else { return false }
        return ["jpg", "jpeg", "png", "gif", "webp", "heic", "bmp", "tiff", "tif"].contains(fileExtension)
    }

    /// File category used for "Open in System App" labelling and icon selection.
    enum OpenableCategory {
        case image, pdf, audio, video, text, document, spreadsheet

        var label: String {
            switch self {
            case .image:       return "Open in Preview"
            case .pdf:         return "Open in Preview"
            case .audio:       return "Open in Music / QuickTime"
            case .video:       return "Open in QuickTime"
            case .text:        return "Open in Text Editor"
            case .document:    return "Open in Pages / Word"
            case .spreadsheet: return "Open in Numbers / Excel"
            }
        }

        var icon: String {
            switch self {
            case .image:       return "photo"
            case .pdf:         return "doc.richtext"
            case .audio:       return "music.note"
            case .video:       return "film"
            case .text:        return "doc.text"
            case .document:    return "doc.fill"
            case .spreadsheet: return "tablecells"
            }
        }
    }

    /// Returns the OpenableCategory if this file can be opened by a macOS default app, otherwise nil.
    var openableCategory: OpenableCategory? {
        guard type == .file else { return nil }
        switch fileExtension {
        // Images
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "bmp", "tiff", "tif":
            return .image
        // PDF
        case "pdf":
            return .pdf
        // Audio
        case "mp3", "aac", "wav", "flac", "ogg", "m4a", "aiff", "aif", "opus", "caf":
            return .audio
        // Video
        case "mp4", "mkv", "avi", "mov", "webm", "m4v", "3gp", "ts", "wmv":
            return .video
        // Text / Code
        case "txt", "log", "md", "csv", "rtf", "nfo",
             "json", "xml", "yaml", "yml", "toml", "plist",
             "swift", "py", "js", "ts", "html", "htm", "css",
             "sh", "bash", "zsh", "c", "cpp", "h", "java", "kt", "rb", "go", "rs":
            return .text
        // Documents
        case "doc", "docx", "pages", "odt":
            return .document
        // Spreadsheets
        case "xls", "xlsx", "numbers", "ods":
            return .spreadsheet
        default:
            return nil
        }
    }

    /// Convenience: true when the file has a known system-app handler.
    var isOpenableFile: Bool { openableCategory != nil }

    var sfSymbolName: String {
        switch type {
        case .directory: return "folder.fill"
        case .symlink:   return "link"
        case .unknown:   return "doc.fill"
        case .file:
            switch fileExtension {
            case "jpg", "jpeg", "png", "gif", "webp", "heic", "bmp":
                return "photo.fill"
            case "mp4", "mkv", "avi", "mov", "webm":
                return "film.fill"
            case "mp3", "aac", "wav", "flac", "ogg", "m4a":
                return "music.note"
            case "pdf":
                return "doc.richtext.fill"
            case "zip", "tar", "gz", "rar", "7z", "apk":
                return "archivebox.fill"
            case "txt", "log", "md":
                return "doc.text.fill"
            case "json", "xml", "yaml", "yml", "toml":
                return "curlybraces"
            case "apk":
                return "app.badge.fill"
            default:
                return "doc.fill"
            }
        }
    }

    /// Human-readable file size (e.g. "4.2 MB")
    var displaySize: String {
        guard let bytes = size else { return type == .directory ? "--" : "" }
        if bytes == 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        let exp = min(Int(log2(Double(bytes)) / 10), units.count - 1)
        let value = Double(bytes) / pow(1024.0, Double(exp))
        return exp == 0
            ? "\(bytes) B"
            : String(format: "%.1f %@", value, units[exp])
    }

    // MARK: - Parsing

    /// Parse a single line from `adb shell ls -la <path>` output.
    ///
    /// Example lines:
    /// ```
    /// drwxrwx--x 17 root  sdcard_rw       3452 2024-01-15 10:23 Android
    /// -rw-rw----  1 root  sdcard_rw    1048576 2024-01-15 10:23 bigfile.mp4
    /// lrwxrwxrwx  1 root  root              12 2024-01-15 10:23 symlink -> /target
    /// ```
    static func from(lsLine line: String, parentPath: String) -> FileNode? {
        // Tokenise, but preserve the tail (name may contain spaces).
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // First character encodes type: d=dir, l=symlink, -=file, c/b/p/s=special
        let firstChar = trimmed.first!
        let fileType: FileType
        switch firstChar {
        case "d": fileType = .directory
        case "l": fileType = .symlink
        case "-": fileType = .file
        default:  fileType = .unknown
        }

        // Split into tokens. We need at least 7 (perms links owner group size date time name)
        // Android `ls -la` sometimes merges date+time into a single token; handle both.
        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard tokens.count >= 6 else { return nil }

        let permissions = tokens[0]
        // tokens[1] = link count (ignore)
        let owner  = tokens[2]
        let group  = tokens[3]

        // Detect whether size token exists (directories often show "4096" or similar).
        // Some restricted Android root entries output "?" for unknown fields — skip them.
        var cursor = 4
        let parsedSize: Int64?
        if cursor < tokens.count {
            if let size = Int64(tokens[cursor]) {
                parsedSize = size
                cursor += 1
            } else {
                parsedSize = nil
                // Skip any leading "?" placeholder tokens so they don't bleed into the name
                while cursor < tokens.count && tokens[cursor] == "?" {
                    cursor += 1
                }
            }
        } else {
            parsedSize = nil
        }

        // Date + time (may be "2024-01-15 10:23" or a single token like "2024-01-15").
        // Also skip "?" placeholder date/time tokens.
        var dateStr: String = ""
        if cursor < tokens.count {
            let maybeDate = tokens[cursor]
            if maybeDate.contains("-") && maybeDate != "?" {
                dateStr = maybeDate
                cursor += 1
                if cursor < tokens.count, tokens[cursor].contains(":") {
                    dateStr += " " + tokens[cursor]
                    cursor += 1
                }
            } else if maybeDate == "?" {
                // Skip unknown date + optional time placeholder
                cursor += 1
                if cursor < tokens.count && (tokens[cursor] == "?" || tokens[cursor].contains(":")) {
                    cursor += 1
                }
            }
        }

        // Everything left is the name (handles spaces in filenames)
        guard cursor < tokens.count else { return nil }
        let rawName = tokens[cursor...].joined(separator: " ")

        // Handle symlink: "name -> target"
        var name = rawName
        var symlinkTarget: String? = nil
        if fileType == .symlink, let arrowRange = rawName.range(of: " -> ") {
            name = String(rawName[rawName.startIndex..<arrowRange.lowerBound])
            symlinkTarget = String(rawName[arrowRange.upperBound...])
        }

        // Skip navigation entries
        if name == "." || name == ".." { return nil }

        let fullPath = parentPath == "/"
            ? "/\(name)"
            : "\(parentPath)/\(name)"

        return FileNode(
            name: name,
            path: fullPath,
            type: fileType,
            permissions: permissions,
            owner: owner,
            group: group,
            size: parsedSize,
            modifiedDate: dateStr.isEmpty ? nil : dateStr,
            symlinkTarget: symlinkTarget
        )
    }
}
