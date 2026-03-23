import SwiftUI
import AppKit

// MARK: - ImagePreviewView

/// Full-screen image preview sheet.
/// Supports pinch-to-zoom, scroll-to-zoom, fit/actual-size toggle, and copy-to-clipboard.
struct ImagePreviewView: View {

    let item: FileBrowserViewModel.ImagePreviewItem
    @Environment(\.dismiss) private var dismiss

    // Zoom state
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var fitMode: Bool = true   // true = fit-to-window

    private let minScale: CGFloat = 0.1
    private let maxScale: CGFloat = 10.0

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            imageArea
            Divider()
            bottomBar
        }
        .frame(minWidth: 600, idealWidth: 800,
               minHeight: 500, idealHeight: 640)
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.fill")
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.file.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.file.path)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .help("Close  Esc")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Image area

    @ViewBuilder
    private var imageArea: some View {
        if item.isLoading {
            loadingView
        } else if let error = item.error {
            errorView(error)
        } else if let url = item.localURL, let nsImage = NSImage(contentsOf: url) {
            zoomableImage(nsImage)
        } else {
            errorView("Could not load image.")
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Downloading from device…")
                .foregroundStyle(Color.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func zoomableImage(_ nsImage: NSImage) -> some View {
        GeometryReader { geo in
            let naturalScale = min(
                geo.size.width  / nsImage.size.width,
                geo.size.height / nsImage.size.height
            )

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width:  fitMode ? geo.size.width  : nsImage.size.width  * scale,
                        height: fitMode ? geo.size.height : nsImage.size.height * scale
                    )
                    .scaleEffect(fitMode ? 1 : 1, anchor: .center)
                    .offset(fitMode ? .zero : offset)
            }
            // Scroll-wheel zoom (trackpad pinch or mouse wheel)
            .onScrollWheel { event in
                if event.modifierFlags.contains(.command) || abs(event.deltaY) > 0 {
                    let delta = event.deltaY
                    let factor: CGFloat = delta < 0 ? 1.1 : 0.9
                    fitMode = false
                    scale = min(max(scale * factor, minScale), maxScale)
                }
            }
            // Dragging to pan
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !fitMode {
                            offset = CGSize(
                                width:  lastOffset.width  + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            // Double-click: toggle fit / 100%
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if fitMode {
                        // Switch to actual size
                        scale = 1.0 / naturalScale
                        offset = .zero
                        lastOffset = .zero
                        fitMode = false
                    } else {
                        // Back to fit
                        fitMode = true
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
        }
        .background(Color(NSColor.underPageBackgroundColor))
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: 12) {
            // File size
            if let size = item.file.size {
                Text(item.file.displaySize)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                Text("·")
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    .font(.caption)
                // Image dimensions (loaded only when we have the URL)
                if let url = item.localURL, let img = NSImage(contentsOf: url) {
                    Text(verbatim: "\(Int(img.size.width)) × \(Int(img.size.height)) px")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                let _ = size   // silence unused warning
            }

            Spacer()

            // Zoom controls (only when image is loaded)
            if !item.isLoading, item.error == nil, item.localURL != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        fitMode = true
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help("Fit to window")

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        fitMode = false
                        scale = max(scale / 1.25, minScale)
                    }
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Zoom out")

                Text(fitMode ? "Fit" : "\(Int(scale * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.secondary)
                    .frame(width: 42, alignment: .center)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        fitMode = false
                        scale = min(scale * 1.25, maxScale)
                    }
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Zoom in")

                Divider().frame(height: 14)

                // Copy to clipboard
                Button {
                    if let url = item.localURL, let img = NSImage(contentsOf: url) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([img])
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .help("Copy image to clipboard")

                // Reveal in Finder
                Button {
                    if let url = item.localURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal temp file in Finder")
            }

            Divider().frame(height: 14)

            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - NSScrollView scroll-wheel helper

/// A view-modifier helper that forwards NSScrollView wheel events to a Swift closure.
private extension View {
    func onScrollWheel(perform action: @escaping (NSEvent) -> Void) -> some View {
        ScrollWheelRepresentable(content: self, action: action)
    }
}

private struct ScrollWheelRepresentable<Content: View>: NSViewRepresentable {
    let content: Content
    let action: (NSEvent) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let host = ScrollWheelNSView(action: action)
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: host.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        return host
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {}
}

private final class ScrollWheelNSView: NSView {
    let action: (NSEvent) -> Void
    init(action: @escaping (NSEvent) -> Void) {
        self.action = action
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func scrollWheel(with event: NSEvent) {
        action(event)
        super.scrollWheel(with: event)
    }
}
