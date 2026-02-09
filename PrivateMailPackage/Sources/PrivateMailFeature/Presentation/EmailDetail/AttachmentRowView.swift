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
        HStack(spacing: 12) {
            fileTypeIcon
            fileInfo
            Spacer()
            actionButtons
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(accessibilityHintText)
        .accessibilityIdentifier("attachment-row-\(attachment.id)")
        .onAppear {
            if attachment.isDownloaded {
                downloadState = .downloaded
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
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }

    // MARK: - File Info

    private var fileInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(attachment.filename)
                .font(.subheadline)
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if case .error(let message) = downloadState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
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
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Download \(attachment.filename)")

        case .downloading:
            HStack(spacing: 8) {
                // TODO: V1 stub — use determinate ProgressView(value:total:) when
                // real download with progress reporting is wired (FR-ED-03 requires
                // determinate progress when sizeBytes is known). Wire
                // DownloadAttachmentUseCaseProtocol to return AsyncStream<Double>.
                ProgressView()

                Button {
                    cancelDownload()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel download")
            }

        case .downloaded:
            HStack(spacing: 12) {
                Button {
                    onPreview(attachment)
                } label: {
                    Image(systemName: "eye")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Preview \(attachment.filename)")

                Button {
                    if let path = attachment.localPath {
                        onShare(URL(fileURLWithPath: path))
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share \(attachment.filename)")
            }

        case .error:
            Button {
                initiateDownload()
            } label: {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.title3)
                    .foregroundStyle(.tint)
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
