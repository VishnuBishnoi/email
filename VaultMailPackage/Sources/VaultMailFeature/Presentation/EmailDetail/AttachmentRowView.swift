import SwiftUI

/// A single attachment row in the email detail view.
/// Shows file type icon, filename, size, and download/action controls.
///
/// Download flow:
///  1. Check `securityWarning` before starting download
///  2. Show progress during download with cancel option
///  3. Offer preview and share actions once downloaded
///
/// Spec ref: Email Detail FR-ED-03
struct AttachmentRowView: View {
    let attachment: Attachment
    let downloadUseCase: DownloadAttachmentUseCaseProtocol
    var onPreview: (Attachment) -> Void
    var onShare: (URL) -> Void

    // MARK: - Environment

    #if os(iOS)
    @Environment(NetworkMonitor.self) private var networkMonitor
    #endif

    // MARK: - State

    @State private var downloadState: DownloadState = .notDownloaded
    @State private var downloadTask: Task<Void, Never>?
    @State private var showSecurityAlert = false
    @State private var securityMessage = ""
    @State private var showCellularAlert = false
    @State private var pendingSecurityWarning: String?
    /// Validated local file URL, computed asynchronously to avoid blocking the main thread.
    @State private var validatedFileURL: URL?
    @Environment(ThemeProvider.self) private var theme

    // MARK: - Download State

    enum DownloadState: Equatable {
        case notDownloaded
        case downloading
        case downloaded
        case error(String)
    }

    // MARK: - Derived Properties

    private var fileIcon: String {
        let mime = attachment.mimeType.lowercased()
        if mime.hasPrefix("image/") { return "photo" }
        if mime == "application/pdf" { return "doc.fill" }
        if mime.hasPrefix("text/") { return "doc.text" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime.hasPrefix("video/") { return "film" }
        return "paperclip"
    }

    private var formattedSize: String {
        Self.formatBytes(attachment.sizeBytes)
    }

    private var downloadStateLabel: String {
        switch downloadState {
        case .notDownloaded: "Not downloaded"
        case .downloading: "Downloading"
        case .downloaded: "Downloaded"
        case .error(let message): "Error: \(message)"
        }
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: theme.spacing.md) {
            fileTypeIcon
            fileInfo
            Spacer()
            actionButtons
        }
        .padding(.vertical, theme.spacing.chipVertical)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(accessibilityHintText)
        .accessibilityIdentifier("attachment-row-\(attachment.id)")
        .onTapGesture {
            if case .downloaded = downloadState {
                if validatedFileURL != nil {
                    onPreview(attachment)
                } else {
                    // Persisted metadata can outlive cache files; re-download when missing.
                    downloadState = .notDownloaded
                    initiateDownload()
                }
            }
        }
        .task(id: attachment.localPath) {
            validatedFileURL = await validateLocalFile()
            if attachment.isDownloaded, validatedFileURL != nil {
                downloadState = .downloaded
            } else if downloadState != .downloading {
                downloadState = .notDownloaded
            }
        }
        .alert("Security Warning", isPresented: $showSecurityAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Download Anyway") {
                startDownload()
            }
        } message: {
            Text(securityMessage)
        }
        .alert("Large Download", isPresented: $showCellularAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Download") {
                // If there's a pending security warning, show that next
                if let warning = pendingSecurityWarning {
                    pendingSecurityWarning = nil
                    securityMessage = warning
                    showSecurityAlert = true
                } else {
                    startDownload()
                }
            }
        } message: {
            Text("This attachment is \(formattedSize). Download on cellular?")
        }
    }

    // MARK: - File Type Icon

    private var fileTypeIcon: some View {
        Image(systemName: fileIcon)
            .font(theme.typography.titleSmall)
            .foregroundStyle(theme.colors.textSecondary)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }

    // MARK: - File Info

    private var fileInfo: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxs) {
            Text(attachment.filename)
                .font(theme.typography.bodyMedium)
                .lineLimit(1)

            HStack(spacing: theme.spacing.xs) {
                Text(formattedSize)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)

                if case .error(let message) = downloadState {
                    Text(message)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.destructive)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        switch downloadState {
        case .notDownloaded:
            Button {
                initiateDownload()
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(theme.typography.titleSmall)
                    .foregroundStyle(theme.colors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Download \(attachment.filename)")

        case .downloading:
            HStack(spacing: theme.spacing.sm) {
                // TODO: V1 stub — use determinate ProgressView(value:total:) when
                // real download with progress reporting is wired (FR-ED-03 requires
                // determinate progress when sizeBytes is known). Wire
                // DownloadAttachmentUseCaseProtocol to return AsyncStream<Double>.
                ProgressView()

                Button {
                    cancelDownload()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(theme.typography.bodyMedium)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel download")
            }

        case .downloaded:
            HStack(spacing: theme.spacing.sm) {
                #if os(macOS)
                // Save attachment to disk via NSSavePanel
                Button {
                    if let fileURL = validatedFileURL {
                        saveToDownloads(fileURL)
                    }
                } label: {
                    Image(systemName: "arrow.down.to.line")
                        .font(theme.typography.bodyMedium)
                        .foregroundStyle(theme.colors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save \(attachment.filename)")
                .help("Save As…")

                // Share button — uses overlay anchor for correct NSSharingServicePicker position
                SharePickerButton(fileURL: validatedFileURL)
                    .accessibilityLabel("Share \(attachment.filename)")
                #else
                Button {
                    if let fileURL = validatedFileURL {
                        onShare(fileURL)
                    } else {
                        downloadState = .notDownloaded
                        initiateDownload()
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(theme.typography.bodyMedium)
                        .foregroundStyle(theme.colors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share \(attachment.filename)")
                #endif
            }

        case .error:
            Button {
                initiateDownload()
            } label: {
                Image(systemName: "arrow.clockwise.circle")
                    .font(theme.typography.titleSmall)
                    .foregroundStyle(theme.colors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry download")
        }
    }

    // MARK: - Download Logic

    private func initiateDownload() {
        let securityWarning = downloadUseCase.securityWarning(for: attachment.filename)
        let needsCellularWarning = isCellular && downloadUseCase.requiresCellularWarning(sizeBytes: attachment.sizeBytes)

        // Per spec FR-ED-03: cellular warning MUST appear in addition to security warning
        if needsCellularWarning {
            pendingSecurityWarning = securityWarning
            showCellularAlert = true
        } else if let warning = securityWarning {
            securityMessage = warning
            showSecurityAlert = true
        } else {
            startDownload()
        }
    }

    /// Whether the device is currently on a cellular connection.
    /// PR #8 Comment 7: Uses the long-lived NetworkMonitor service instead
    /// of creating an ad-hoc NWPathMonitor (which returns stale data).
    private var isCellular: Bool {
        #if os(iOS)
        return networkMonitor.isCellular
        #else
        return false
        #endif
    }

    private func startDownload() {
        downloadState = .downloading
        downloadTask = Task {
            do {
                _ = try await downloadUseCase.download(attachment: attachment)
                downloadState = .downloaded
            } catch {
                if Task.isCancelled { return }
                downloadState = .error(error.localizedDescription)
            }
        }
    }

    private func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadState = .notDownloaded
    }

    #if os(macOS)
    /// Presents an NSSavePanel so the user can choose where to save the attachment.
    /// This works correctly with App Sandbox since NSSavePanel grants write access
    /// to the user-chosen location.
    private func saveToDownloads(_ sourceURL: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        // Default to Downloads folder
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        panel.begin { response in
            guard response == .OK, let destinationURL = panel.url else { return }
            do {
                // Remove existing file if user chose to overwrite
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                NSLog("[Attachment] Failed to save attachment: \(error.localizedDescription)")
            }
        }
    }
    #endif

    // MARK: - Size Formatting

    static func formatBytes(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(bytes) B"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    /// Validates the local file exists and isn't a legacy base64-encoded text file.
    /// Captures attachment properties on the main actor, then performs file I/O
    /// off the main thread to avoid blocking the UI.
    private func validateLocalFile() async -> URL? {
        // Capture Sendable values on the main actor before switching contexts.
        guard let path = attachment.localPath else { return nil }
        let mimeType = attachment.mimeType

        return await Task.detached {
            let fileURL = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

            // Detect legacy corrupted files that contain raw base64 text
            // instead of decoded binary content.
            if !mimeType.lowercased().hasPrefix("text/"),
               let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
               !data.isEmpty {
                let sample = data.prefix(min(1024, data.count))
                if AttachmentFileUtilities.looksLikeBase64(sample) {
                    return nil
                }
            }

            return fileURL
        }.value
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts: [String] = []
        parts.append(attachment.filename)
        parts.append(formattedSize)
        parts.append(downloadStateLabel)
        return parts.joined(separator: ", ")
    }

    private var accessibilityHintText: String {
        switch downloadState {
        case .notDownloaded:
            "Double-tap to download"
        case .downloading:
            "Downloading in progress"
        case .downloaded:
            "Double-tap to preview"
        case .error:
            "Double-tap to retry download"
        }
    }
}

// MARK: - macOS Share Picker Button

#if os(macOS)
import AppKit

/// A macOS button that shows `NSSharingServicePicker` anchored to itself.
///
/// Uses an `NSViewRepresentable` to capture the underlying `NSView`, ensuring
/// the share picker appears next to the button rather than at the window center.
private struct SharePickerButton: View {
    let fileURL: URL?
    @Environment(ThemeProvider.self) private var theme

    var body: some View {
        Button {
            // Action handled by the overlay's NSView tap
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.accent)
        }
        .buttonStyle(.plain)
        .help("Share")
        .overlay {
            SharePickerAnchorView(fileURL: fileURL)
        }
    }
}

/// An invisible `NSViewRepresentable` overlay that captures the `NSView` anchor
/// and presents `NSSharingServicePicker` on click.
private struct SharePickerAnchorView: NSViewRepresentable {
    let fileURL: URL?

    func makeNSView(context: Context) -> SharePickerNSView {
        let view = SharePickerNSView()
        view.fileURL = fileURL
        return view
    }

    func updateNSView(_ nsView: SharePickerNSView, context: Context) {
        nsView.fileURL = fileURL
    }
}

/// Transparent `NSView` that responds to clicks by presenting the share picker.
private final class SharePickerNSView: NSView {
    var fileURL: URL?

    override func mouseDown(with event: NSEvent) {
        guard let fileURL else {
            super.mouseDown(with: event)
            return
        }
        let picker = NSSharingServicePicker(items: [fileURL])
        picker.show(relativeTo: bounds, of: self, preferredEdge: .minY)
    }
}
#endif

// MARK: - Previews

#if os(iOS)
#Preview("Not Downloaded") {
    let attachment = Attachment(
        filename: "quarterly-report.pdf",
        mimeType: "application/pdf",
        sizeBytes: 2_450_000
    )

    List {
        AttachmentRowView(
            attachment: attachment,
            downloadUseCase: PreviewDownloadUseCase(),
            onPreview: { _ in },
            onShare: { _ in }
        )
    }
    .environment(NetworkMonitor())
    .environment(ThemeProvider())
}

#Preview("Downloaded") {
    let attachment = Attachment(
        filename: "photo.jpg",
        mimeType: "image/jpeg",
        sizeBytes: 845_000,
        localPath: "/tmp/photo.jpg",
        isDownloaded: true
    )

    List {
        AttachmentRowView(
            attachment: attachment,
            downloadUseCase: PreviewDownloadUseCase(),
            onPreview: { _ in },
            onShare: { _ in }
        )
    }
    .environment(NetworkMonitor())
    .environment(ThemeProvider())
}

#Preview("Multiple Attachments") {
    let attachments = [
        Attachment(filename: "notes.txt", mimeType: "text/plain", sizeBytes: 1200),
        Attachment(filename: "song.mp3", mimeType: "audio/mpeg", sizeBytes: 5_600_000),
        Attachment(filename: "video.mp4", mimeType: "video/mp4", sizeBytes: 128_000_000),
        Attachment(filename: "archive.zip", mimeType: "application/zip", sizeBytes: 45_000_000),
    ]

    List {
        ForEach(attachments, id: \.id) { attachment in
            AttachmentRowView(
                attachment: attachment,
                downloadUseCase: PreviewDownloadUseCase(),
                onPreview: { _ in },
                onShare: { _ in }
            )
        }
    }
    .environment(NetworkMonitor())
    .environment(ThemeProvider())
}
#endif

// MARK: - Preview Helper

@MainActor
private final class PreviewDownloadUseCase: DownloadAttachmentUseCaseProtocol {
    func download(attachment: Attachment) async throws -> String {
        try await Task.sleep(for: .seconds(1))
        let path = NSTemporaryDirectory() + attachment.filename
        attachment.isDownloaded = true
        attachment.localPath = path
        return path
    }

    func securityWarning(for filename: String) -> String? {
        nil
    }

    func requiresCellularWarning(sizeBytes: Int) -> Bool {
        false
    }
}
