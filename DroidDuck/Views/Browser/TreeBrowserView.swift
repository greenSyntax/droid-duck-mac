import SwiftUI

// MARK: - TreeBrowserView

/// Renders the file system as an expandable tree.
/// Children are loaded lazily — only when a directory is first expanded.
struct TreeBrowserView: View {

    @EnvironmentObject var vm: FileBrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header: collapse-all button + node count
            HStack {
                Button {
                    vm.collapseAllTreeNodes()
                } label: {
                    Label("Collapse All", systemImage: "arrow.up.to.line")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Collapse all expanded folders")
                .disabled(vm.visibleTreeNodes.isEmpty)

                Spacer()

                Text("\(vm.visibleTreeNodes.count) visible items")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if vm.visibleTreeNodes.isEmpty && !vm.isLoading {
                emptyView
            } else {
                List(vm.visibleTreeNodes) { node in
                    TreeRowView(node: node)
                        .listRowInsets(EdgeInsets(
                            top: 1,
                            leading: CGFloat(node.depth) * 16,
                            bottom: 1,
                            trailing: 8
                        ))
                        .environmentObject(vm)
                }
                .listStyle(.inset)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 40))
                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            Text("Empty folder")
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - TreeRowView

struct TreeRowView: View {

    /// Using @ObservedObject so the row re-renders when isLoading / isExpanded change.
    @ObservedObject var node: FileBrowserViewModel.TreeNode
    @EnvironmentObject var vm: FileBrowserViewModel

    var body: some View {
        HStack(spacing: 4) {
            // Expand / collapse triangle (directories) or spacer (files)
            expandButton

            // File icon with optional lock badge
            fileIcon

            // Name + symlink target
            VStack(alignment: .leading, spacing: 1) {
                Text(node.file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(node.file.isSystemEntry ? Color.secondary : Color.primary)

                if node.file.type == .symlink, let target = node.file.symlinkTarget {
                    Text("→ \(target)")
                        .font(.caption2)
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Size
            if let size = node.file.size {
                Text(node.file.displaySize)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
            }

            // Load error indicator
            if let _ = node.loadError {
                Image(systemName: "exclamationmark.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.orange)
                    .help(node.loadError ?? "Failed to load")
            }
        }
        .contentShape(Rectangle())
        .help(node.file.path)
        .onTapGesture(count: 2) {
            if node.file.isDirectory {
                vm.navigate(to: node.file)
            } else if node.file.isImageFile {
                vm.previewImage(for: node.file)
            } else {
                vm.openInSystemApp(for: node.file)
            }
        }
        .contextMenu { contextMenu }
    }

    // MARK: - Expand button

    @ViewBuilder
    private var expandButton: some View {
        if node.file.isDirectory {
            Button {
                vm.toggleTreeNode(node)
            } label: {
                if node.isLoading {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(Color.secondary)
                        .frame(width: 14, height: 14)
                        .animation(.easeInOut(duration: 0.15), value: node.isExpanded)
                }
            }
            .buttonStyle(.plain)
            .help(node.isExpanded ? "Collapse" : "Expand")
        } else {
            // Spacer to align file names with folder names
            Spacer().frame(width: 14)
        }
    }

    // MARK: - File icon

    private var fileIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: node.file.sfSymbolName)
                .imageScale(.small)
                .foregroundStyle(node.file.isSystemEntry ? Color.secondary : iconColor)
                .frame(width: 16)

            if node.file.isSystemEntry || node.file.isReadOnly {
                Image(systemName: "lock.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(Color.secondary)
                    .background(
                        Circle()
                            .fill(Color(NSColor.windowBackgroundColor))
                            .frame(width: 8, height: 8)
                    )
                    .offset(x: 5, y: 3)
            }
        }
        .frame(width: 20)
    }

    private var iconColor: Color {
        switch node.file.type {
        case .directory: return .accentColor
        case .symlink:   return .purple
        case .unknown:   return .secondary
        case .file:
            switch node.file.fileExtension {
            case "jpg", "jpeg", "png", "gif", "webp", "heic", "bmp": return .pink
            case "mp4", "mkv", "avi", "mov", "webm":                  return .orange
            case "mp3", "aac", "wav", "flac", "ogg", "m4a":           return .mint
            case "pdf":                                                return .red
            case "zip", "tar", "gz", "rar", "7z", "apk":             return .brown
            default:                                                   return .secondary
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        // --- Navigate / Open ---
        if node.file.isDirectory {
            Button { vm.toggleTreeNode(node) } label: {
                Label(node.isExpanded ? "Collapse" : "Expand",
                      systemImage: node.isExpanded ? "chevron.up" : "chevron.down")
            }
            Button { vm.navigate(to: node.file) } label: {
                Label("Navigate Into Folder", systemImage: "folder.fill")
            }
            Divider()
        } else if node.file.isImageFile {
            Button { vm.previewImage(for: node.file) } label: {
                Label("Quick Preview", systemImage: "eye")
            }
        }

        if let category = node.file.openableCategory {
            Button { vm.openInSystemApp(for: node.file) } label: {
                Label(category.label, systemImage: category.icon)
            }
            Divider()
        }

        // --- Download ---
        Button { vm.downloadToMac(file: node.file) } label: {
            Label("Download to Mac", systemImage: "arrow.down.circle")
        }
        .disabled(node.file.isDirectory)

        Divider()

        // --- Clipboard ---
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.file.path, forType: .string)
        } label: {
            Label("Copy Path", systemImage: "doc.on.clipboard")
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.file.name, forType: .string)
        } label: {
            Label("Copy Name", systemImage: "character.cursor.ibeam")
        }

        Divider()

        Button { vm.showInfo(for: node.file) } label: {
            Label("Get Info", systemImage: "info.circle")
        }

        Divider()

        if !node.file.isSystemEntry {
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
