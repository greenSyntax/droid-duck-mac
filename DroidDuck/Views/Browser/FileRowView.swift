import SwiftUI
import AppKit

// MARK: - FileRowView

struct FileRowView: View {

    let file: FileNode
    @EnvironmentObject var vm: FileBrowserViewModel

    var body: some View {
        HStack(spacing: 10) {
            fileIcon
            fileName
            Spacer()
            fileSize
            fileDate
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        // 1. Tooltip showing full path on hover
        .help(file.path)
        // 3. Right-click context menu
        .contextMenu { contextMenuItems }
        // Double-click: navigate folder / quick-preview image / open other file types
        .onTapGesture(count: 2) {
            if file.isDirectory {
                vm.navigate(to: file)
            } else if file.isImageFile {
                vm.previewImage(for: file)
            } else {
                vm.openInSystemApp(for: file)
            }
        }
    }

    // MARK: - Icon

    private var fileIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: file.sfSymbolName)
                .imageScale(.medium)
                // 2. System files get muted grey; regular files keep their colour
                .foregroundStyle(file.isSystemEntry ? Color.secondary : iconColor)
                .frame(width: 20)

            // Lock badge for system / read-only entries
            if file.isSystemEntry || file.isReadOnly {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.secondary)
                    .background(
                        Circle()
                            .fill(Color(NSColor.windowBackgroundColor))
                            .frame(width: 10, height: 10)
                    )
                    .offset(x: 6, y: 4)
            }
        }
        .frame(width: 26)
    }

    // MARK: - Name

    private var fileName: some View {
        HStack(spacing: 4) {
            Text(file.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(file.isSystemEntry ? Color.secondary : Color.primary)

            if file.type == .symlink, let target = file.symlinkTarget {
                Text("→ \(target)")
                    .font(.caption)
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    // MARK: - Metadata columns

    private var fileSize: some View {
        Text(file.displaySize)
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .frame(width: 72, alignment: .trailing)
            .monospacedDigit()
    }

    @ViewBuilder
    private var fileDate: some View {
        if let date = file.modifiedDate {
            Text(date)
                .font(.caption)
                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                .frame(width: 120, alignment: .trailing)
        }
    }

    // MARK: - Icon colour (non-system files)

    private var iconColor: Color {
        switch file.type {
        case .directory: return .accentColor
        case .symlink:   return .purple
        case .unknown:   return .secondary
        case .file:
            switch file.fileExtension {
            case "jpg", "jpeg", "png", "gif", "webp", "heic", "bmp": return .pink
            case "mp4", "mkv", "avi", "mov", "webm":                  return .orange
            case "mp3", "aac", "wav", "flac", "ogg", "m4a":           return .mint
            case "pdf":                                                return .red
            case "zip", "tar", "gz", "rar", "7z", "apk":             return .brown
            default:                                                   return .secondary
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {

        // --- Navigate / Open ---
        if file.isDirectory {
            Button {
                vm.navigate(to: file)
            } label: {
                Label("Open", systemImage: "folder.fill")
            }
            Divider()
        } else if file.isImageFile {
            // In-app preview (fast, no app switch)
            Button {
                vm.previewImage(for: file)
            } label: {
                Label("Quick Preview", systemImage: "eye")
            }
        }

        // Open in system default app for all openable types
        if let category = file.openableCategory {
            Button {
                vm.openInSystemApp(for: file)
            } label: {
                Label(category.label, systemImage: category.icon)
            }
            Divider()
        }

        // --- Download ---
        Button {
            vm.downloadToMac(file: file)
        } label: {
            Label("Download to Mac", systemImage: "arrow.down.circle")
        }
        // Allow download for all files (not just openable ones)
        .disabled(file.isDirectory)

        if file.isDirectory {
            Button { } label: {
                Label("New Folder Inside", systemImage: "folder.badge.plus")
            }
            .disabled(true)
        }

        Divider()

        // --- Clipboard ---
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.path, forType: .string)
        } label: {
            Label("Copy Path", systemImage: "doc.on.clipboard")
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.name, forType: .string)
        } label: {
            Label("Copy Name", systemImage: "character.cursor.ibeam")
        }

        Divider()

        // --- Info ---
        Button {
            vm.showInfo(for: file)
        } label: {
            Label("Get Info", systemImage: "info.circle")
        }

        Divider()

        // --- Destructive ---
        if !file.isSystemEntry {
            Button { } label: {
                Label("Rename", systemImage: "pencil")
            }
            .disabled(true)

            Button(role: .destructive) { } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(true)
        } else {
            Button { } label: {
                Label("System File — Cannot Delete", systemImage: "lock.fill")
            }
            .disabled(true)
        }
    }
}
