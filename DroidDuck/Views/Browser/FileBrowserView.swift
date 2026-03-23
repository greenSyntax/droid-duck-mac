import SwiftUI

// MARK: - FileBrowserView

struct FileBrowserView: View {

    let device: DeviceInfo
    @EnvironmentObject var vm: FileBrowserViewModel

    @FocusState private var searchFocused: Bool

    /// Computed separately so the TextField receives a plain `String`,
    /// not a `LocalizedStringKey` — string interpolation inside a TextField
    /// label literal causes a compiler error.
    private var searchPlaceholder: String {
        let component = URL(fileURLWithPath: vm.currentPath).lastPathComponent
        return "Search in \(component.isEmpty ? "/" : component)…"
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            // Show search bar when active, breadcrumb bar otherwise
            if vm.isSearchActive {
                searchBar
            } else {
                breadcrumbBar
            }
            Divider()
            content
        }
        .navigationTitle(device.displayName)
        .navigationSubtitle(vm.isSearchActive ? "Searching in \(vm.currentPath)" : vm.currentPath)
        .sheet(item: $vm.infoFile) { file in
            FileInfoView(file: file)
        }
        .sheet(item: $vm.imagePreview) { item in
            ImagePreviewView(item: item)
        }
        // Download / Open-in-System-App status banner
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FileActionBanner(state: vm.fileOpenState) {
                vm.dismissOpenState()
            }
        }
        // ⌘F / Esc handled via hidden buttons (avoids onKeyPress API differences across macOS versions)
        .background(
            Group {
                Button("") {
                    if !vm.isSearchActive { vm.activateSearch(); searchFocused = true }
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("") {
                    if vm.isSearchActive { vm.dismissSearch() }
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .opacity(0)
        )
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            // Back
            Button { vm.goBack() } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!vm.canGoBack)
            .help("Go Back")
            .keyboardShortcut("[", modifiers: .command)

            // Forward
            Button { vm.goForward() } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!vm.canGoForward)
            .help("Go Forward")
            .keyboardShortcut("]", modifiers: .command)

            Divider().frame(height: 16)

            // Internal Storage (primary home)
            Button { vm.goToStorage() } label: {
                Image(systemName: "internaldrive")
            }
            .help("Internal Storage  /sdcard")

            // Root
            Button { vm.goHome() } label: {
                Image(systemName: "externaldrive")
            }
            .help("Root  /")

            Divider().frame(height: 16)

            // Refresh
            Button { vm.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(vm.isLoading ? .degrees(360) : .zero)
                    .animation(
                        vm.isLoading
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: vm.isLoading
                    )
            }
            .help("Refresh current folder  ⌘R")
            .keyboardShortcut("r")

            Spacer()

            // Item count + system file legend
            if !vm.isSearchActive && !vm.files.isEmpty {
                let systemCount = vm.files.filter(\.isSystemEntry).count
                HStack(spacing: 8) {
                    if systemCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill")
                                .imageScale(.small)
                                .foregroundStyle(Color.secondary)
                            Text("\(systemCount) system")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                        .help("System files are read-only and cannot be modified")
                    }
                    Text("\(vm.files.count) items")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }

            Divider().frame(height: 16)

            // List / Tree / Card toggle
            Picker("", selection: Binding(
                get: { vm.viewMode },
                set: { vm.setViewMode($0) }
            )) {
                Image(systemName: "list.bullet")
                    .tag(FileBrowserViewModel.ViewMode.list)
                    .help("List View")
                Image(systemName: "list.bullet.indent")
                    .tag(FileBrowserViewModel.ViewMode.tree)
                    .help("Tree View")
                Image(systemName: "square.grid.2x2")
                    .tag(FileBrowserViewModel.ViewMode.card)
                    .help("Card View")
            }
            .pickerStyle(.segmented)
            .frame(width: 82)
            .help({
                switch vm.viewMode {
                case .list: return "Switch to Tree View"
                case .tree: return "Switch to Card View"
                case .card: return "Switch to List View"
                }
            }())

            Divider().frame(height: 16)

            // Search toggle button
            Button {
                if vm.isSearchActive {
                    vm.dismissSearch()
                } else {
                    vm.activateSearch()
                    searchFocused = true
                }
            } label: {
                Image(systemName: vm.isSearchActive ? "xmark.circle.fill" : "magnifyingglass")
            }
            .help(vm.isSearchActive ? "Close Search  Esc" : "Search Files  ⌘F")
            .foregroundStyle(vm.isSearchActive ? Color.secondary : Color.primary)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Breadcrumb bar

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(vm.breadcrumbs.enumerated()), id: \.offset) { idx, crumb in
                    if idx > 0 {
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    }
                    Button {
                        vm.navigate(toPath: crumb.path)
                    } label: {
                        Text(crumb.label)
                            .font(.system(size: 12))
                            .foregroundStyle(idx == vm.breadcrumbs.count - 1 ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(crumb.path)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.secondary)

            TextField(searchPlaceholder, text: $vm.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit { vm.performSearch() }
                .onChange(of: vm.searchQuery) { vm.performSearch() }

            if vm.isSearching {
                ProgressView().scaleEffect(0.6)
            } else if !vm.searchQuery.isEmpty {
                Button {
                    vm.searchQuery = ""
                    vm.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("Esc to close")
                .font(.caption2)
                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Content area

    @ViewBuilder
    private var content: some View {
        if vm.isSearchActive {
            searchResultsView
        } else if vm.isLoading && vm.files.isEmpty {
            loadingView
        } else if let error = vm.errorMessage {
            errorView(error)
        } else if vm.files.isEmpty {
            emptyFolderView
        } else if vm.viewMode == .tree {
            TreeBrowserView()
                .environmentObject(vm)
        } else if vm.viewMode == .card {
            CardBrowserView()
                .environmentObject(vm)
        } else {
            fileList
        }
    }

    // MARK: - Search results

    @ViewBuilder
    private var searchResultsView: some View {
        if vm.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            // Prompt state
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 38))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                Text("Type to search files in \(vm.currentPath)")
                    .foregroundStyle(Color.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        } else if vm.isSearching && vm.searchResults.isEmpty {
            // Searching spinner
            VStack(spacing: 10) {
                ProgressView()
                Text("Searching…")
                    .foregroundStyle(Color.secondary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        } else if let err = vm.searchError {
            errorView(err)

        } else if vm.searchResults.isEmpty {
            // No results
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 38))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                Text(verbatim: "No results for \"\(vm.searchQuery)\"")
                    .font(.callout)
                    .foregroundStyle(Color.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        } else {
            // Results list
            VStack(spacing: 0) {
                // Result count header
                HStack {
                    Text(verbatim: "\(vm.searchResults.count) result\(vm.searchResults.count == 1 ? "" : "s") for \"\(vm.searchQuery)\"")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    if vm.isSearching {
                        ProgressView().scaleEffect(0.6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                List(vm.searchResults) { result in
                    SearchResultRowView(result: result)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { vm.navigateInto(result: result) }
                        .contextMenu {
                            Button {
                                vm.navigateInto(result: result)
                            } label: {
                                Label(result.isDirectory ? "Open Folder" : "Show in Folder",
                                      systemImage: result.isDirectory ? "folder.fill" : "folder")
                            }
                            Divider()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(result.path, forType: .string)
                            } label: {
                                Label("Copy Path", systemImage: "doc.on.clipboard")
                            }
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(result.name, forType: .string)
                            } label: {
                                Label("Copy Name", systemImage: "character.cursor.ibeam")
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
    }

    private var fileList: some View {
        List(vm.files, selection: $vm.selectedFile) { file in
            FileRowView(file: file)
                .tag(file)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if file.isDirectory { vm.navigate(to: file) }
                }
        }
        .listStyle(.inset)
        .overlay(alignment: .top) {
            if vm.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Empty / Loading / Error states

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading…")
                .font(.callout)
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFolderView: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 40))
                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            Text("Empty folder")
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button("Retry") { vm.refresh() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SearchResultRowView

struct SearchResultRowView: View {
    let result: FileBrowserViewModel.SearchResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.sfSymbolName)
                .imageScale(.medium)
                .foregroundStyle(result.isDirectory ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                // Filename
                Text(result.name)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Parent path
                Text(result.parentPath)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            Image(systemName: "arrow.right.circle")
                .imageScale(.small)
                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
        }
        .padding(.vertical, 2)
        .help("Double-click to \(result.isDirectory ? "open folder" : "show in parent folder")")
    }
}

// MARK: - FileInfoView

/// Simple "Get Info" sheet shown from the context menu.
struct FileInfoView: View {

    let file: FileNode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: file.sfSymbolName)
                    .font(.system(size: 36))
                    .foregroundStyle(file.isSystemEntry ? Color.secondary : Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name)
                        .font(.title3.bold())
                        .textSelection(.enabled)
                    Text(file.type == .directory ? "Folder" : "File")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Info rows
            ScrollView {
                VStack(spacing: 0) {
                    infoRow("Path",        file.path)
                    infoRow("Kind",        kindString)
                    infoRow("Size",        file.size.map { "\($0) bytes (\(file.displaySize))" } ?? "—")
                    infoRow("Modified",    file.modifiedDate ?? "—")
                    infoRow("Permissions", file.permissions ?? "—")
                    infoRow("Owner",       file.owner ?? "—")
                    infoRow("Group",       file.group ?? "—")
                    if let target = file.symlinkTarget {
                        infoRow("Points to", target)
                    }
                    infoRow("System file", file.isSystemEntry ? "Yes (read-only)" : "No")
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 420, height: 360)
    }

    private var kindString: String {
        switch file.type {
        case .directory: return "Folder"
        case .symlink:   return "Symbolic Link"
        case .file:      return file.fileExtension.isEmpty ? "File" : "\(file.fileExtension.uppercased()) File"
        case .unknown:   return "Unknown"
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .frame(width: 100, alignment: .trailing)
                .padding(.trailing, 12)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
        return Divider().padding(.leading, 120)
    }
}
