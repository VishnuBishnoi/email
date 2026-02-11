#if os(iOS)
import Foundation
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Input Models

/// Local file model used by the attachment preview flow.
///
/// Quick Look and UIActivityViewController both expect local file URLs, so this
/// type only accepts local file paths.
struct AttachmentPreviewFile: Identifiable, Equatable {
    let id: String
    let fileURL: URL
    let displayName: String

    init(id: String, fileURL: URL, displayName: String? = nil) {
        self.id = id
        self.fileURL = fileURL
        self.displayName = displayName ?? fileURL.lastPathComponent
    }
}

/// Attachment bytes model used when callers need this kit to persist data first.
struct AttachmentPreviewPayload {
    let filename: String
    let mimeType: String?
    let data: Data

    init(filename: String, mimeType: String? = nil, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

// MARK: - File Store

enum AttachmentPreviewFileStore {

    /// Saves bytes to a temp file and returns a local URL that can be previewed/shared.
    static func saveToTemporaryDirectory(_ payload: AttachmentPreviewPayload) throws -> URL {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent("EmailAttachments", isDirectory: true)
        if !manager.fileExists(atPath: base.path) {
            try manager.createDirectory(at: base, withIntermediateDirectories: true)
        }

        let safeName = sanitizeFilename(payload.filename)
        let resolvedName = ensureExtensionIfMissing(filename: safeName, mimeType: payload.mimeType)
        let target = base.appendingPathComponent(resolvedName)

        if manager.fileExists(atPath: target.path) {
            try manager.removeItem(at: target)
        }

        try payload.data.write(to: target, options: .atomic)
        return target
    }

    private static func sanitizeFilename(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Attachment" : cleaned
    }

    private static func ensureExtensionIfMissing(filename: String, mimeType: String?) -> String {
        let url = URL(fileURLWithPath: filename)
        if !url.pathExtension.isEmpty { return filename }

        guard let mimeType,
              let utType = UTType(mimeType: mimeType),
              let ext = utType.preferredFilenameExtension,
              !ext.isEmpty else {
            return filename
        }
        return "\(filename).\(ext)"
    }
}

// MARK: - Quick Look Item

private final class AttachmentQLPreviewItem: NSObject, QLPreviewItem {
    let fileURL: URL
    let title: String

    init(fileURL: URL, title: String) {
        self.fileURL = fileURL
        self.title = title
        super.init()
    }

    var previewItemURL: URL? { fileURL }
    var previewItemTitle: String? { title }
}

// MARK: - Quick Look Controller

private final class AttachmentQLPreviewController: QLPreviewController {
    var onMoreTapped: ((UIBarButtonItem) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        let button = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(moreTapped)
        )
        button.accessibilityLabel = "More attachment actions"
        navigationItem.rightBarButtonItem = button
    }

    @objc private func moreTapped(_ sender: UIBarButtonItem) {
        onMoreTapped?(sender)
    }
}

// MARK: - Reusable Presenter

/// UIKit presenter for attachment preview + share/open/save.
///
/// Behavior:
/// - Uses `QLPreviewController` to preview and swipe between attachments.
/// - Adds a "More" button that opens `UIActivityViewController`.
/// - If tapped item is not Quick Look previewable, skips preview and opens activity sheet.
@MainActor
final class AttachmentPreviewPresenter: NSObject {
    private var items: [AttachmentQLPreviewItem] = []

    func makeViewController(files: [AttachmentPreviewFile], initialIndex: Int) -> UIViewController? {
        guard !files.isEmpty else { return nil }
        items = files.map { AttachmentQLPreviewItem(fileURL: $0.fileURL, title: $0.displayName) }

        let clampedIndex = max(0, min(initialIndex, items.count - 1))
        let selectedItem = items[clampedIndex]

        // Fallback: if this type is not Quick Look previewable, still provide open/share/save.
        if !QLPreviewController.canPreview(selectedItem) {
            return makeShareSheet(for: selectedItem.fileURL, in: nil, barButtonItem: nil)
        }

        let previewController = AttachmentQLPreviewController()
        previewController.dataSource = self
        previewController.delegate = self
        previewController.currentPreviewItemIndex = clampedIndex
        previewController.onMoreTapped = { [weak self, weak previewController] barButton in
            guard let self, let previewController else { return }
            let currentIndex = previewController.currentPreviewItemIndex
            let safeIndex = max(0, min(currentIndex, self.items.count - 1))
            let activity = self.makeShareSheet(
                for: self.items[safeIndex].fileURL,
                in: previewController.view,
                barButtonItem: barButton
            )
            previewController.present(activity, animated: true)
        }

        return UINavigationController(rootViewController: previewController)
    }

    func present(
        files: [AttachmentPreviewFile],
        initialIndex: Int,
        from presentingViewController: UIViewController
    ) {
        guard let controller = makeViewController(files: files, initialIndex: initialIndex) else {
            return
        }
        if let activity = controller as? UIActivityViewController,
           let popover = activity.popoverPresentationController,
           popover.sourceView == nil {
            popover.sourceView = presentingViewController.view
            popover.sourceRect = CGRect(
                x: presentingViewController.view.bounds.midX,
                y: presentingViewController.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        presentingViewController.present(controller, animated: true)
    }

    func present(
        payloads: [AttachmentPreviewPayload],
        initialIndex: Int,
        from presentingViewController: UIViewController
    ) {
        do {
            let files = try payloads.map { payload in
                let url = try AttachmentPreviewFileStore.saveToTemporaryDirectory(payload)
                return AttachmentPreviewFile(id: UUID().uuidString, fileURL: url, displayName: payload.filename)
            }
            present(files: files, initialIndex: initialIndex, from: presentingViewController)
        } catch {
            let alert = UIAlertController(
                title: "Unable to open attachment",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            presentingViewController.present(alert, animated: true)
        }
    }

    private func makeShareSheet(
        for url: URL,
        in sourceView: UIView?,
        barButtonItem: UIBarButtonItem?
    ) -> UIActivityViewController {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            if let barButtonItem {
                popover.barButtonItem = barButtonItem
            } else {
                popover.sourceView = sourceView
                popover.sourceRect = CGRect(
                    x: sourceView?.bounds.midX ?? 0,
                    y: sourceView?.bounds.midY ?? 0,
                    width: 1,
                    height: 1
                )
                popover.permittedArrowDirections = []
            }
        }
        return activity
    }
}

extension AttachmentPreviewPresenter: QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        items.count
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        items[index]
    }
}

// MARK: - SwiftUI Bridge

/// SwiftUI wrapper around `AttachmentPreviewPresenter`.
///
/// This allows SwiftUI screens to use the same UIKit preview/share flow used by
/// UIKit screens, instead of duplicating preview logic.
struct AttachmentPreviewSheet: UIViewControllerRepresentable {
    let files: [AttachmentPreviewFile]
    let initialIndex: Int

    func makeUIViewController(context: Context) -> UIViewController {
        if let controller = context.coordinator.presenter.makeViewController(
            files: files,
            initialIndex: initialIndex
        ) {
            return controller
        }
        return UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        let presenter = AttachmentPreviewPresenter()
    }
}

// MARK: - Previews

#Preview("Attachment Preview Sheet") {
    AttachmentPreviewSheet(
        files: [AttachmentPreviewFile(
            id: "sample",
            fileURL: URL(fileURLWithPath: "/tmp/sample.pdf"),
            displayName: "sample.pdf"
        )],
        initialIndex: 0
    )
}
#endif
