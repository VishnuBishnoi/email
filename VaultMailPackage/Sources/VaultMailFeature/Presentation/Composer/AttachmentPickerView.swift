import SwiftUI
#if os(iOS)
import PhotosUI
import UniformTypeIdentifiers
#elseif os(macOS)
import UniformTypeIdentifiers
#endif

/// Attachment picker and list for the email composer.
///
/// Supports file picker and photo library on iOS. Each attachment
/// displays filename, size, and a remove button. Warns when total
/// size exceeds 25 MB.
///
/// Spec ref: Email Composer FR-COMP-01
struct AttachmentPickerView: View {
    @Environment(ThemeProvider.self) private var theme
    @Binding var attachments: [AttachmentItem]
    @State private var showDocumentPicker = false
    @State private var showPhotoPicker = false
    #if os(iOS)
    @State private var selectedPhotos: [PhotosPickerItem] = []
    #endif

    /// Total attachment size in bytes.
    private var totalSizeBytes: Int {
        attachments.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Whether total size exceeds the limit (strictly greater than max).
    private var isOverLimit: Bool {
        totalSizeBytes > AppConstants.maxAttachmentSizeMB * 1024 * 1024
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.sm) {
            // Attachment list
            if !attachments.isEmpty {
                ForEach(attachments) { item in
                    attachmentRow(for: item)
                }

                // Size warning
                if isOverLimit {
                    Label(
                        "Attachments exceed \(AppConstants.maxAttachmentSizeMB) MB limit",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.destructive)
                    .padding(.horizontal, theme.spacing.lg)
                }
            }

            // Add attachment menu
            Menu {
                Button {
                    showDocumentPicker = true
                } label: {
                    Label("Choose File...", systemImage: "doc")
                }

                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Choose Photo...", systemImage: "photo")
                }
            } label: {
                Label("Add Attachment", systemImage: "paperclip")
                    .font(theme.typography.bodyMedium)
            }
            .padding(.horizontal, theme.spacing.lg)
        }
        .padding(.vertical, theme.spacing.sm)
        #if os(iOS)
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerRepresentable { urls in
                addFilesFromURLs(urls)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos, maxSelectionCount: 10, matching: .images)
        .onChange(of: selectedPhotos) { _, newItems in
            Task { await addPhotos(from: newItems) }
            selectedPhotos = []
        }
        #elseif os(macOS)
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                addFilesFromURLs(urls)
            }
        }
        .fileImporter(
            isPresented: $showPhotoPicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                addFilesFromURLs(urls)
            }
        }
        #endif
    }

    // MARK: - Attachment Row

    @ViewBuilder
    private func attachmentRow(for item: AttachmentItem) -> some View {
        HStack {
            Image(systemName: iconForMimeType(item.mimeType))
                .foregroundStyle(theme.colors.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(theme.typography.bodyMedium)
                    .lineLimit(1)
                Text(item.formattedSize)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer()

            if item.isDownloading {
                ProgressView()
                    .controlSize(.small)
            }

            Button(role: .destructive) {
                removeAttachment(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.filename)")
        }
        .padding(.horizontal, theme.spacing.lg)
        .padding(.vertical, theme.spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.filename), \(item.formattedSize)")
        .accessibilityAction(named: "Remove") {
            removeAttachment(item)
        }
    }

    // MARK: - Actions

    private func removeAttachment(_ item: AttachmentItem) {
        attachments.removeAll { $0.id == item.id }
    }

    private func addFilesFromURLs(_ urls: [URL]) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            let name = url.lastPathComponent
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

            // Copy file to temp directory while security scope is active.
            // After defer releases the scope, the original URL may be inaccessible.
            let localPath: String?
            if let data = try? Data(contentsOf: url) {
                let uniqueName = "\(UUID().uuidString.prefix(8))_\(name)"
                localPath = Self.writeToTempDirectory(data: data, filename: uniqueName)
            } else {
                localPath = nil
            }

            let item = AttachmentItem(
                filename: name,
                sizeBytes: size,
                mimeType: mimeType,
                localPath: localPath
            )
            attachments.append(item)
        }
    }

    #if os(iOS)
    private func addPhotos(from items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let filename = "Photo_\(UUID().uuidString.prefix(8)).\(ext)"

            // Write photo data to temp directory so executeSend() can read it later.
            // Without this, the Data only exists in memory and localPath would be nil.
            let localPath = Self.writeToTempDirectory(data: data, filename: filename)

            let attachment = AttachmentItem(
                filename: filename,
                sizeBytes: data.count,
                mimeType: mimeType,
                localPath: localPath
            )
            attachments.append(attachment)
        }
    }
    #endif

    /// Writes attachment data to a persistent temp directory.
    ///
    /// Returns the file path on success, nil on failure.
    /// Files persist until explicitly cleaned via ``cleanupTempAttachments()``.
    private static func writeToTempDirectory(data: Data, filename: String) -> String? {
        let dir = tempAttachmentsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            return fileURL.path
        } catch {
            return nil
        }
    }

    /// The temp directory used for attachment staging.
    static let tempAttachmentsDirectory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("attachments", isDirectory: true)

    /// Removes all files from the temp attachments directory.
    ///
    /// Call after a successful send or when the composer is dismissed
    /// without sending to avoid unbounded disk growth.
    static func cleanupTempAttachments() {
        let dir = tempAttachmentsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Helpers

    private func iconForMimeType(_ mimeType: String) -> String {
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType.hasPrefix("video/") { return "film" }
        if mimeType.contains("pdf") { return "doc.richtext" }
        if mimeType.contains("zip") || mimeType.contains("compressed") { return "doc.zipper" }
        return "doc"
    }
}

// MARK: - Document Picker (iOS)

#if os(iOS)
struct DocumentPickerRepresentable: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
#endif

// MARK: - Previews

#Preview("No Attachments") {
    AttachmentPickerView(attachments: .constant([]))
        .environment(ThemeProvider())
}

#Preview("With Attachments") {
    AttachmentPickerView(attachments: .constant([
        AttachmentItem(filename: "document.pdf", sizeBytes: 2_500_000, mimeType: "application/pdf"),
        AttachmentItem(filename: "photo.jpg", sizeBytes: 1_200_000, mimeType: "image/jpeg"),
        AttachmentItem(filename: "archive.zip", sizeBytes: 15_000_000, mimeType: "application/zip")
    ]))
    .environment(ThemeProvider())
}

#Preview("Over Limit") {
    AttachmentPickerView(attachments: .constant([
        AttachmentItem(filename: "large_video.mp4", sizeBytes: 20_000_000, mimeType: "video/mp4"),
        AttachmentItem(filename: "backup.zip", sizeBytes: 10_000_000, mimeType: "application/zip")
    ]))
    .environment(ThemeProvider())
}
