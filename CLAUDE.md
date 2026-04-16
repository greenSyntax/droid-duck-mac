# CLAUDE.md — DroidDuck

Reference file for Claude when working on this project. Covers architecture, conventions, key patterns, and implementation notes.

---

## Project Overview

**DroidDuck** is a native macOS file explorer for Android devices, built with **Swift + SwiftUI**. It uses ADB (Android Debug Bridge) under the hood to list, browse, preview, and download files from a connected Android phone/tablet — no third-party apps required.

- **Platform**: macOS 13 Ventura+
- **Language**: Swift 5.9+ / SwiftUI
- **Xcode**: 15+
- **Dependency**: ADB (auto-installed via Homebrew if missing)
- **App Sandbox**: Must be **disabled** (ADB subprocess won't work inside sandbox)

---

## Architecture

The app follows a clean **MVVM + Services** pattern.

```
DroidDuck/
├── DroidDuckApp.swift              # @main entry, menu bar commands, sheets
├── Models/
│   ├── DeviceInfo.swift            # Device model + connection status enum
│   └── FileNode.swift              # File/folder model, ls parser, file categories
├── Services/
│   ├── ADBService.swift            # actor — all ADB shell calls go here
│   └── DeviceManager.swift        # @MainActor ObservableObject — device polling & state
├── ViewModels/
│   └── FileBrowserViewModel.swift  # Navigation, search, tree, thumbnails, open/download
└── Views/
    ├── ContentView.swift            # NavigationSplitView root
    ├── Sidebar/
    │   └── DeviceSidebarView.swift  # Devices + Locations panel
    ├── Browser/
    │   ├── FileBrowserView.swift    # Toolbar, breadcrumbs, search bar, content routing
    │   ├── FileRowView.swift        # List view row
    │   ├── TreeBrowserView.swift    # Expandable tree view
    │   ├── CardBrowserView.swift    # Card grid with lazy thumbnails
    │   └── ImagePreviewView.swift   # Full-screen image preview sheet
    └── Shared/
        ├── DiagnosticsView.swift    # System diagnostics report
        ├── EmptyStateView.swift     # No-ADB / no-device empty state
        └── FileActionBanner.swift   # Slide-up download/open status banner
```

---

## Key Patterns & Conventions

### ADBService — `actor`
`ADBService` is a Swift `actor` (singleton via `ADBService.shared`). All ADB interactions are serialised through it. Never call ADB commands directly from views or view models — always go through this actor.

```swift
// ✅ Correct
let files = try await ADBService.shared.listDirectory(serial: serial, path: path)

// ❌ Avoid — never spawn raw Processes from views
```

### DeviceManager — `@MainActor` `ObservableObject`
`DeviceManager` owns the list of connected devices and the selected device. It's injected as an `@EnvironmentObject` from `DroidDuckApp` and polls every **3 seconds**. Views should read from it reactively, not imperatively.

### FileBrowserViewModel — `@MainActor` `ObservableObject`
Handles all navigation state: current path, back/forward history, search query, view mode (list/tree/card), thumbnail cache, and file open/download states. Each view that needs browsing context should receive this as `@StateObject` or `@ObservedObject`.

### Path Escaping
All paths passed to ADB shell commands must go through `ADBService.escapedPath(_:)` which wraps them in single quotes and escapes embedded single quotes. **Never interpolate raw paths directly into shell commands.**

### File Parsing
`FileNode.from(lsLine:parentPath:)` parses a single line of `adb shell ls -la` output. It handles:
- Directories (`d`), symlinks (`l`), regular files (`-`), unknowns
- Variable token counts (Android `ls` is not POSIX-standard)
- `?` placeholder tokens from restricted paths
- Symlink arrows (`name -> target`)
- Spaces in file names

### System Files
`FileNode.isSystemEntry` returns `true` for paths under known Android OS prefixes (`/system`, `/vendor`, `/apex`, `/proc`, etc.). These are rendered with a lock badge and muted colour in all view modes and should **never** be offered for write operations.

---

## ADB Setup & Discovery

ADB is looked up in this order at bootstrap:
1. `/opt/homebrew/bin/adb` (Apple Silicon Homebrew)
2. `/usr/local/bin/adb` (Intel Homebrew)
3. `~/Library/Android/sdk/platform-tools/adb` (Android Studio)
4. `~/Android/sdk/platform-tools/adb`
5. `/usr/bin/adb`
6. Output of `/usr/bin/which adb`

If not found and Homebrew is present, the app offers to auto-install `android-platform-tools` with live streaming output (`DeviceManager.installADB()`).

---

## Views & Navigation

### View Modes
Three modes exist: **List** (default), **Tree** (lazy-loading), **Card** (grid with thumbnails). Switching mode is controlled in `FileBrowserViewModel`. All three read from the same `[FileNode]` array.

### Sidebar Locations
Quick-jump targets are hardcoded in `DeviceSidebarView`:
`/sdcard`, Downloads, Camera, Pictures, Music, Movies, Documents, WhatsApp, Android data, Root (`/`)

### Navigation History
Back/forward history is managed as a stack in `FileBrowserViewModel`. Use `navigate(to:)` to push a new path (this clears the forward stack). `goBack()` / `goForward()` move through history.

### Context Menu
Right-click on any file or folder exposes:
- Quick Preview (images only)
- Open in System App (pulls file to temp, opens with macOS default handler)
- Download to Mac (saves to `~/Downloads`, auto-renames on collision, reveals in Finder)
- Copy Path / Copy Name
- Get Info (full metadata sheet)

---

## File Operations

### Pull / Open
Files are pulled to `NSTemporaryDirectory()/DroidDuck/<hash>_<filename>` via `ADBService.pullFile(serial:remotePath:)`. The hash prefix prevents collisions when two files share the same name. Status is surfaced via `FileActionBanner` (slide-up from bottom).

### Download to Mac
Target: `~/Downloads/<filename>`. If a file already exists, a numeric suffix is appended (`file (1).txt`, etc.). Finder reveals the file on completion.

### Thumbnails (Card View)
Thumbnails are pulled lazily as cards scroll into view, with a concurrency cap of **4** simultaneous pulls. Results are cached in-memory in `FileBrowserViewModel`.

---

## Search

- Triggered by **⌘F**, dismissed by **Esc**
- Debounced **400 ms** to avoid ADB spam
- Runs `adb shell find <path> -maxdepth 10 -iname '*query*'` in two parallel passes (files and directories)
- Capped at 200 file + 100 directory results
- Shell-injection-safe: strips `'`, `"`, `;`, `|`, `&` from query before building command
- Results are displayed grouped: directories first, each row shows its parent path

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| ⌘R | Refresh current directory |
| ⌘[ | Go back |
| ⌘] | Go forward |
| ⌘F | Activate search |
| Esc | Dismiss search |
| ⌘⇧R | Refresh device list |
| ⌘⌥D | Open Diagnostics |

---

## Known Limitations / Upcoming Work

- **Write operations** (rename, delete, new folder) are not yet implemented
- **APK installation** not yet supported
- Directories cannot be downloaded as a zip — file-only downloads for now
- Large video files may take time to pull before QuickTime opens

---

## Development Notes

- **No App Sandbox** — must be removed in Xcode under Target → Signing & Capabilities. ADB subprocess will be blocked if sandbox is active.
- **Concurrency model**: ADB calls → `actor ADBService` (background); UI state → `@MainActor` classes. Avoid dispatching to `DispatchQueue.main` — use `await MainActor.run {}` or mark types `@MainActor` instead.
- **SwiftUI Environment**: `DeviceManager` is passed via `.environmentObject()` from the app root. `FileBrowserViewModel` is typically `@StateObject` in the view that owns the browser.
- **Error handling**: `ADBError` is `LocalizedError`. Surface errors through `DeviceManager.errorMessage` (for device-level) or `FileBrowserViewModel` error state (for file-level). Don't show raw `error.localizedDescription` to the user without context.
- **Process execution**: Always use `ADBService.runRaw(executable:args:)` — never pass the bare string `"adb"` as the executable path; it must be an absolute path or the process will throw at runtime.

---

## Build & Run

```bash
git clone https://github.com/greenSyntax/droid-duck-mac.git
cd DroidDuck
open DroidDuck/DroidDuck.xcodeproj
# In Xcode: remove App Sandbox capability, then ⌘R
```

Manual ADB install (if needed):
```bash
brew install --cask android-platform-tools
```
