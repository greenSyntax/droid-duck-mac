import SwiftUI
import AppKit

// MARK: - AboutView

struct AboutView: View {

    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // --- Header ---
            VStack(spacing: 14) {
                Image("img_android")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)

                VStack(spacing: 4) {
                    Text("DroidDuck")
                        .font(.system(size: 22, weight: .bold))

                    Text(appVersion)
                        .font(.callout)
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.top, 32)
            .padding(.bottom, 20)

            Divider()

            // --- Description ---
            VStack(spacing: 16) {
                Text("A native macOS file explorer for connected Android devices. Browse, preview, and transfer files from your Android phone or tablet — no third-party apps required.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 340)

                // --- Links ---
                VStack(spacing: 8) {
                    LinkRow(
                        icon: "globe",
                        label: "greensyntax.cloud",
                        url: "http://greensyntax.cloud"
                    )

                    LinkRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        label: "github.com/greemSyntax/droid-duck-mac",
                        url: "https://github.com/greemSyntax/droid-duck-mac"
                    )
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)

            Divider()

            // --- Footer ---
            HStack {
                Text("© 2025 GreenSyntax. MIT License.")
                    .font(.caption)
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 420)
        .fixedSize()
    }
}

// MARK: - LinkRow

private struct LinkRow: View {

    let icon: String
    let label: String
    let url: String

    @State private var isHovered = false

    var body: some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .imageScale(.small)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 16)

                Text(label)
                    .font(.callout)
                    .foregroundStyle(isHovered ? Color.accentColor : Color.primary)
                    .underline(isHovered)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .imageScale(.small)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isHovered
                          ? Color.accentColor.opacity(0.08)
                          : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
