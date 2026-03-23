import SwiftUI

// MARK: - FileActionBanner

/// A slim status banner shown at the bottom of the file browser while a file
/// is being pulled from the device (for Open-in-System-App or Download-to-Mac).
///
/// Appears with a slide-up animation and disappears automatically on success
/// or after 5 seconds on failure.
struct FileActionBanner: View {

    let state: FileBrowserViewModel.FileOpenState
    let onDismiss: () -> Void

    var body: some View {
        // Only render anything when not idle
        if state != .idle {
            HStack(spacing: 10) {
                icon
                message
                Spacer()
                dismissButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state)
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .idle:
            EmptyView()
        case .downloading:
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 18, height: 18)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.medium)
        }
    }

    @ViewBuilder
    private var message: some View {
        switch state {
        case .idle:
            EmptyView()
        case .downloading(let name):
            VStack(alignment: .leading, spacing: 1) {
                Text("Downloading from device…")
                    .font(.callout)
                Text(name)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .failed(let name, let error):
            VStack(alignment: .leading, spacing: 1) {
                let title = "Failed to open \"\(name)\""
                Text(verbatim: title)
                    .font(.callout)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var dismissButton: some View {
        Button {
            onDismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.secondary)
        }
        .buttonStyle(.plain)
        .help("Dismiss")
    }
}
