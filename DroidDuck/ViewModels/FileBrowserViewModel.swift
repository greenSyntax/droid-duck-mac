import Foundation
import Combine
import AppKit

// MARK: - FileBrowserViewModel

/// Manages navigation state and file listing for a connected device.
@MainActor
final class FileBrowserViewModel: ObservableObject {

    // MARK: - Published State

    // MARK: - View Mode

    enum ViewMode { case list, tree, card }
    @Published var viewMode: ViewMode = .list

    // MARK: - Tree Node

    /// A single node in the lazy-loaded tree.
    /// `@MainActor` so all mutations happen on the main thread safely.
    @MainActor
    final class TreeNode: ObservableObject, Identifiable {
        let id: String          // stable = file path
        let file: FileNode
        let depth: Int

        @Published var children: [TreeNode] = []
        @Published var isExpanded: Bool = false
        @Published var isLoading: Bool = false
        @Published var loadError: String? = nil

        /// True when children haven't been fetched yet (distinguished from
        /// "fetched but empty" by checking `isExpanded`).
        var childrenLoaded: Bool = false

        init(file: FileNode, depth: Int) {
            self.id    = file.path
            self.file  = file
            self.depth = depth
        }
    }

    @Published var visibleTreeNodes: [TreeNode] = []   // flat, rebuilt on expand/collapse
    private var treeRoots: [TreeNode] = []

    // MARK: - File Listing

    @Published var files: [FileNode] = []
    @Published var currentPath: String = "/"
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var selectedFile: FileNode? = nil
    @Published var infoFile: FileNode? = nil   // drives the Get Info sheet

    // MARK: - Search State

    @Published var searchQuery: String = ""
    @Published var isSearchActive: Bool = false
    @Published var isSearching: Bool = false
    @Published var searchResults: [SearchResult] = []
    @Published var searchError: String? = nil

    // MARK: - Image Preview State

    /// Drives the image-preview sheet.
    struct ImagePreviewItem: Identifiable {
        let id   = UUID()
        let file: FileNode
        var localURL: URL?   = nil
        var isLoading: Bool  = true
        var error: String?   = nil
    }

    @Published var imagePreview: ImagePreviewItem? = nil

    // MARK: - System App Open State

    /// Tracks the pull-then-open lifecycle for "Open in System App".
    enum FileOpenState: Equatable {
        case idle
        case downloading(String)          // filename currently being pulled
        case failed(String, String)       // filename, error message

        static func == (lhs: FileOpenState, rhs: FileOpenState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle):
                return true
            case (.downloading(let a), .downloading(let b)):
                return a == b
            case (.failed(let a1, let a2), .failed(let b1, let b2)):
                return a1 == b1 && a2 == b2
            default:
                return false
            }
        }
    }

    @Published var fileOpenState: FileOpenState = .idle
    private var autoDismissTask: Task<Void, Never>? = nil

    // MARK: - Thumbnail Cache (Card View)

    enum ThumbnailState {
        case loading
        case loaded(NSImage)
        case failed
    }

    @Published var thumbnailCache: [String: ThumbnailState] = [:]

    /// How many pulls are currently in-flight for thumbnails.
    private var activeThumbLoads: Int = 0
    private let maxConcurrentThumbLoads = 4
    /// Paths queued but not yet started.
    private var thumbQueue: [FileNode] = []

    /// Request a thumbnail for `file`. No-op if already cached or not an image.
    func requestThumbnail(for file: FileNode) {
        guard file.isImageFile else { return }
        guard thumbnailCache[file.path] == nil else { return }    // already cached/loading

        thumbnailCache[file.path] = .loading

        if activeThumbLoads < maxConcurrentThumbLoads {
            startThumbLoad(file)
        } else {
            thumbQueue.append(file)
        }
    }

    private func startThumbLoad(_ file: FileNode) {
        activeThumbLoads += 1
        let serial = deviceSerial
        Task {
            defer {
                activeThumbLoads -= 1
                // Drain queue: pick the next waiting item
                if !thumbQueue.isEmpty {
                    let next = thumbQueue.removeFirst()
                    startThumbLoad(next)
                }
            }
            do {
                let url   = try await ADBService.shared.pullFile(serial: serial, remotePath: file.path)
                if let img = NSImage(contentsOf: url) {
                    thumbnailCache[file.path] = .loaded(img)
                } else {
                    thumbnailCache[file.path] = .failed
                }
            } catch {
                thumbnailCache[file.path] = .failed
            }
        }
    }

    /// Wipe thumbnail cache and cancel pending queue (call on detach or device change).
    private func clearThumbnailCache() {
        thumbQueue.removeAll()
        thumbnailCache.removeAll()
        // Note: in-flight tasks will complete and write to the cache, but the cache
        // will be replaced on next attach so the stale entries are harmless.
    }

    private var searchTask: Task<Void, Never>? = nil

    struct SearchResult: Identifiable {
        let id = UUID()
        let path: String
        let isDirectory: Bool

        var name: String { URL(fileURLWithPath: path).lastPathComponent }
        var parentPath: String { URL(fileURLWithPath: path).deletingLastPathComponent().path }

        // Derive a display icon from the file extension
        var sfSymbolName: String {
            if isDirectory { return "folder.fill" }
            let ext = (name as NSString).pathExtension.lowercased()
            switch ext {
            case "jpg", "jpeg", "png", "gif", "webp", "heic", "bmp": return "photo.fill"
            case "mp4", "mkv", "avi", "mov", "webm":                  return "film.fill"
            case "mp3", "aac", "wav", "flac", "ogg", "m4a":           return "music.note"
            case "pdf":                                                return "doc.richtext.fill"
            case "zip", "tar", "gz", "rar", "7z", "apk":             return "archivebox.fill"
            case "txt", "log", "md":                                   return "doc.text.fill"
            case "json", "xml", "yaml", "yml", "toml":                return "curlybraces"
            default:                                                   return "doc.fill"
            }
        }
    }

    // MARK: - Navigation History

    private var backStack: [String] = []
    private var forwardStack: [String] = []

    var canGoBack: Bool    { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Breadcrumb components derived from the current path.
    var breadcrumbs: [(label: String, path: String)] {
        guard currentPath != "/" else {
            return [("/", "/")]
        }
        var crumbs: [(label: String, path: String)] = [("/", "/")]
        var accumulated = ""
        for component in currentPath.split(separator: "/") {
            accumulated += "/\(component)"
            crumbs.append((String(component), accumulated))
        }
        return crumbs
    }

    // MARK: - Device binding

    /// The serial of the device being browsed. Set by ContentView when selection changes.
    private var deviceSerial: String = ""

    // MARK: - Public API

    /// Call when a new device is selected or the view appears.
    func attach(serial: String) {
        guard serial != deviceSerial else { return }
        deviceSerial = serial
        backStack = []
        forwardStack = []
        currentPath = StorageLocation.internalStorage.path
        Task { await load(path: StorageLocation.internalStorage.path, pushToHistory: false) }
    }

    /// Detach from the current device (e.g. device disconnected).
    func detach() {
        deviceSerial = ""
        files = []
        currentPath = "/"
        backStack = []
        forwardStack = []
        errorMessage = nil
        treeRoots = []
        visibleTreeNodes = []
        clearThumbnailCache()
    }

    // MARK: - Navigation

    func navigate(to node: FileNode) {
        guard node.isDirectory else { return }
        Task { await load(path: node.path, pushToHistory: true) }
    }

    func navigate(toPath path: String) {
        Task { await load(path: path, pushToHistory: true) }
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentPath)
        Task { await load(path: previous, pushToHistory: false) }
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentPath)
        Task { await load(path: next, pushToHistory: false) }
    }

    func goHome() {
        navigate(toPath: "/")
    }

    func goToStorage() {
        navigate(toPath: "/sdcard")
    }

    func refresh() {
        Task { await load(path: currentPath, pushToHistory: false) }
    }

    func showInfo(for file: FileNode) {
        infoFile = file
    }

    /// Pull the image from the device and present the preview sheet.
    func previewImage(for file: FileNode) {
        guard file.isImageFile else { return }
        imagePreview = ImagePreviewItem(file: file)

        let serial = deviceSerial
        Task {
            do {
                let url = try await ADBService.shared.pullFile(serial: serial, remotePath: file.path)
                imagePreview?.localURL  = url
                imagePreview?.isLoading = false
            } catch {
                imagePreview?.error     = error.localizedDescription
                imagePreview?.isLoading = false
            }
        }
    }

    /// Pull the file from the device and open it with the macOS default handler.
    /// Works for any file type — macOS will show an "Open With" picker if no app is registered.
    func openInSystemApp(for file: FileNode) {
        guard file.type != .directory else { return }

        // Cancel any previous auto-dismiss timer
        autoDismissTask?.cancel()
        fileOpenState = .downloading(file.name)

        let serial = deviceSerial
        Task {
            do {
                let url = try await ADBService.shared.pullFile(serial: serial, remotePath: file.path)
                // Open with default macOS handler on main thread
                NSWorkspace.shared.open(url)
                fileOpenState = .idle
            } catch {
                fileOpenState = .failed(file.name, error.localizedDescription)
                // Auto-dismiss the error banner after 5 seconds
                autoDismissTask = Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled else { return }
                    fileOpenState = .idle
                }
            }
        }
    }

    func dismissOpenState() {
        autoDismissTask?.cancel()
        fileOpenState = .idle
    }

    /// Pull the file from the device and save it to the user's Downloads folder,
    /// then reveal it in Finder.
    func downloadToMac(file: FileNode) {
        autoDismissTask?.cancel()
        fileOpenState = .downloading(file.name)

        let serial = deviceSerial
        Task {
            do {
                // Pull to a temp location first
                let tempURL = try await ADBService.shared.pullFile(serial: serial, remotePath: file.path)

                // Move/copy to ~/Downloads
                let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                var destURL = downloadsDir.appendingPathComponent(file.name)

                // Avoid overwriting — append a counter if needed
                var counter = 1
                let baseName = (file.name as NSString).deletingPathExtension
                let ext      = (file.name as NSString).pathExtension
                while FileManager.default.fileExists(atPath: destURL.path) {
                    let newName = ext.isEmpty
                        ? "\(baseName) (\(counter))"
                        : "\(baseName) (\(counter)).\(ext)"
                    destURL = downloadsDir.appendingPathComponent(newName)
                    counter += 1
                }

                try FileManager.default.copyItem(at: tempURL, to: destURL)

                fileOpenState = .idle
                // Reveal in Finder
                NSWorkspace.shared.activateFileViewerSelecting([destURL])
            } catch {
                fileOpenState = .failed(file.name, error.localizedDescription)
                autoDismissTask = Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    guard !Task.isCancelled else { return }
                    fileOpenState = .idle
                }
            }
        }
    }

    // MARK: - Search

    /// Activate the search bar without running a search yet.
    func activateSearch() {
        isSearchActive = true
        searchResults  = []
        searchError    = nil
        searchQuery    = ""
    }

    /// Dismiss search and return to the regular file listing.
    func dismissSearch() {
        searchTask?.cancel()
        isSearchActive = false
        isSearching    = false
        searchQuery    = ""
        searchResults  = []
        searchError    = nil
    }

    /// Run the search. Debounced: cancels any in-flight search first.
    func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !deviceSerial.isEmpty else {
            searchResults = []
            return
        }

        searchTask?.cancel()
        searchTask = Task {
            // Small debounce so we don't hammer ADB on every keystroke
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
            guard !Task.isCancelled else { return }

            await MainActor.run {
                isSearching = true
                searchError = nil
            }

            do {
                let results = try await ADBService.shared.searchFiles(
                    serial: deviceSerial,
                    inPath: currentPath,
                    query: query
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchResults = results.map {
                        SearchResult(path: $0.path, isDirectory: $0.isDirectory)
                    }
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchError = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }

    /// Navigate to the parent folder of a search result.
    func navigateToParent(of result: SearchResult) {
        dismissSearch()
        navigate(toPath: result.parentPath)
    }

    /// Navigate into a search result (if directory).
    func navigateInto(result: SearchResult) {
        if result.isDirectory {
            dismissSearch()
            navigate(toPath: result.path)
        } else {
            navigateToParent(of: result)
        }
    }

    // MARK: - View Mode Switching

    func setViewMode(_ mode: ViewMode) {
        viewMode = mode
        switch mode {
        case .tree: buildTreeFromCurrentFiles()
        case .card: break   // thumbnails are loaded lazily by CardBrowserView
        case .list: break
        }
    }

    // MARK: - Tree Operations

    /// Rebuild tree roots from the already-loaded flat file list.
    private func buildTreeFromCurrentFiles() {
        treeRoots = files.map { TreeNode(file: $0, depth: 0) }
        rebuildVisibleNodes()
    }

    /// Recompute the flat visible array by walking expanded nodes depth-first.
    private func rebuildVisibleNodes() {
        var result: [TreeNode] = []
        func walk(_ nodes: [TreeNode]) {
            for node in nodes {
                result.append(node)
                if node.isExpanded { walk(node.children) }
            }
        }
        walk(treeRoots)
        visibleTreeNodes = result
    }

    /// Toggle expand/collapse for a directory node. Loads children lazily on first expand.
    func toggleTreeNode(_ node: TreeNode) {
        guard node.file.isDirectory else { return }

        if node.isExpanded {
            node.isExpanded = false
            rebuildVisibleNodes()
        } else {
            Task { await expandNode(node) }
        }
    }

    private func expandNode(_ node: TreeNode) async {
        guard !node.isLoading else { return }

        // Load children if not yet fetched
        if !node.childrenLoaded {
            node.isLoading = true
            node.loadError = nil
            do {
                let childFiles = try await ADBService.shared.listDirectory(
                    serial: deviceSerial,
                    path: node.file.path
                )
                node.children = childFiles.map { TreeNode(file: $0, depth: node.depth + 1) }
                node.childrenLoaded = true
            } catch {
                node.loadError = error.localizedDescription
                node.isLoading = false
                return
            }
            node.isLoading = false
        }

        node.isExpanded = true
        rebuildVisibleNodes()
    }

    /// Collapse all nodes and reset tree to root level.
    func collapseAllTreeNodes() {
        func collapseRecursive(_ nodes: [TreeNode]) {
            for node in nodes {
                node.isExpanded = false
                collapseRecursive(node.children)
            }
        }
        collapseRecursive(treeRoots)
        rebuildVisibleNodes()
    }

    // MARK: - Private Loading

    private func load(path: String, pushToHistory: Bool) async {
        guard !deviceSerial.isEmpty else { return }

        if pushToHistory {
            backStack.append(currentPath)
            forwardStack = []  // invalidate forward stack on new navigation
        }

        isLoading = true
        errorMessage = nil
        selectedFile = nil

        do {
            let nodes = try await ADBService.shared.listDirectory(serial: deviceSerial, path: path)
            files = nodes
            currentPath = path
            // Rebuild tree roots when navigating in tree mode
            if viewMode == .tree { buildTreeFromCurrentFiles() }
        } catch let adbError as ADBError {
            errorMessage = adbError.errorDescription
            // Roll back history on failure
            if pushToHistory { backStack.removeLast() }
        } catch {
            errorMessage = error.localizedDescription
            if pushToHistory { backStack.removeLast() }
        }

        isLoading = false
    }
}
