import SwiftUI
import AppKit

// MARK: - CardBrowserView

/// Displays files as a grid of square cards.
/// Image files show a live thumbnail pulled from the device;
/// other file types show a large SF Symbol on a coloured background.
struct CardBrowserView: View {

    @EnvironmentObject var vm: FileBrowserViewModel

    /// Adaptive grid: cards are ~150 pt wide, fill the width.
    private let columns = [GridItem(.adaptive(minimum: 148, maximum: 190), spacing: 10)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(vm.files) { file in
                    CardItemView(file: file)
                        .environmentObject(vm)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - CardItemView

private struct CardItemView: View {

    let file: FileNode
    @EnvironmentObject var vm: FileBrowserViewModel

    /// Highlight when this card is selected.
    private var isSelected: Bool { vm.selectedFile?.id == file.id }

    var body: some View {
        VStack(spacing: 0) {
            // Color.clear sets the square frame first; thumbnailArea overlays on top.
            // This prevents images with non-1:1 aspect ratios from breaking the card height.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(thumbnailArea)
                .clipped()

            Divider()

            // File name
            HStack(spacing: 4) {
                if file.isSystemEntry || file.isReadOnly {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
                Text(file.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
                    .foregroundStyle(file.isSystemEntry ? Color.secondary : Color.primary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 34)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    isSelected ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.6),
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
        // Single tap selects
        .onTapGesture(count: 1) {
            vm.selectedFile = file
        }
        // Double-tap: navigate / preview / open
        .onTapGesture(count: 2) {
            if file.isDirectory {
                vm.navigate(to: file)
            } else if file.isImageFile {
                vm.previewImage(for: file)
            } else {
                vm.openInSystemApp(for: file)
            }
        }
        .contextMenu { CardContextMenu(file: file).environmentObject(vm) }
        // Kick off thumbnail pull when card enters the viewport
        .onAppear {
            vm.requestThumbnail(for: file)
        }
    }

    // MARK: - Thumbnail area

    @ViewBuilder
    private var thumbnailArea: some View {
        if file.isImageFile {
            imageThumbnail
        } else {
            iconThumbnail
        }
    }

    @ViewBuilder
    private var imageThumbnail: some View {
        switch vm.thumbnailCache[file.path] {
        case .loaded(let image):
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        case .loading, nil:
            ZStack {
                Color(NSColor.quaternaryLabelColor).opacity(0.3)
                VStack(spacing: 6) {
                    ProgressView().scaleEffect(0.75)
                    Text("Loading…")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
            }
        case .failed:
            ZStack {
                Color(NSColor.quaternaryLabelColor).opacity(0.3)
                VStack(spacing: 6) {
                    Image(systemName: "photo.slash.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.secondary)
                    Text("Unavailable")
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
    }

    private var iconThumbnail: some View {
        ZStack {
            // Subtle gradient background tinted by the file-type colour
            LinearGradient(
                colors: [iconTint.opacity(0.18), iconTint.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 8) {
                Image(systemName: file.sfSymbolName)
                    .font(.system(size: 44))
                    .foregroundStyle(file.isSystemEntry ? Color.secondary : iconTint)

                // Extension badge
                if !file.fileExtension.isEmpty {
                    Text(file.fileExtension.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle((file.isSystemEntry ? Color.secondary : iconTint).opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill((file.isSystemEntry ? Color.secondary : iconTint).opacity(0.12))
                        )
                }
            }
        }
    }

    // Colour that tints icon backgrounds and SF Symbols for non-image files
    private var iconTint: Color {
        switch file.type {
        case .directory: return .accentColor
        case .symlink:   return .purple
        case .unknown:   return .secondary
        case .file:
            switch file.fileExtension {
            case "jpg","jpeg","png","gif","webp","heic","bmp","tiff","tif": return .pink
            case "mp4","mkv","avi","mov","webm","m4v","3gp","wmv":         return .orange
            case "mp3","aac","wav","flac","ogg","m4a","aiff","aif":        return .mint
            case "pdf":                                                     return .red
            case "zip","tar","gz","rar","7z","apk":                        return .brown
            case "doc","docx","pages","odt":                               return .blue
            case "xls","xlsx","numbers","ods","csv":                       return Color(red: 0.1, green: 0.6, blue: 0.3)
            case "txt","log","md","rtf":                                    return .gray
            case "json","xml","yaml","yml","toml","plist",
                 "swift","py","js","ts","html","htm","css",
                 "sh","bash","c","cpp","h","java","kt","rb","go","rs":     return .teal
            default:                                                        return .secondary
            }
        }
    }
}

// MARK: - CardContextMenu

/// Context menu for a card. Mirrors FileRowView's menu.
private struct CardContextMenu: View {

    let file: FileNode
    @EnvironmentObject var vm: FileBrowserViewModel

    var body: some View {
        // --- Navigate / Open ---
        if file.isDirectory {
            Button { vm.navigate(to: file) } label: {
                Label("Open", systemImage: "folder.fill")
            }
            Divider()
        } else if file.isImageFile {
            Button { vm.previewImage(for: file) } label: {
                Label("Quick Preview", systemImage: "eye")
            }
        }

        if let category = file.openableCategory {
            Button { vm.openInSystemApp(for: file) } label: {
                Label(category.label, systemImage: category.icon)
            }
            Divider()
        }

        // Download
        Button { vm.downloadToMac(file: file) } label: {
            Label("Download to Mac", systemImage: "arrow.down.circle")
        }
        .disabled(file.isDirectory)

        Divider()

        // Clipboard
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

        Button { vm.showInfo(for: file) } label: {
            Label("Get Info", systemImage: "info.circle")
        }

        Divider()

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
