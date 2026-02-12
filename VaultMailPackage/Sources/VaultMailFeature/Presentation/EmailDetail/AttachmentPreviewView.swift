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
    private let minZoomScale: CGFloat = 1.0
    private let maxZoomScale: CGFloat = 8.0
    private let pinchSensitivity: CGFloat = 0.9
    private let zoomSnapThreshold: CGFloat = 0.06
    private let doubleTapZoomScale: CGFloat = 2.5
    private var fallbackZoomScale: CGFloat = 1.0

    override func viewDidLoad() {
        super.viewDidLoad()
        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(moreTapped)
        )
        moreButton.accessibilityLabel = "More attachment actions"
        navigationItem.rightBarButtonItem = moreButton
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        view.addGestureRecognizer(pinch)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        view.addGestureRecognizer(doubleTap)
    }

    @objc private func moreTapped(_ sender: UIBarButtonItem) {
        onMoreTapped?(sender)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let scrollView = findZoomableScrollView(in: view) else { return }

        if scrollView.minimumZoomScale >= scrollView.maximumZoomScale {
            scrollView.minimumZoomScale = minZoomScale
            scrollView.maximumZoomScale = maxZoomScale
        }

        let adjustedScale = pow(gesture.scale, pinchSensitivity)

        if scrollView.maximumZoomScale > scrollView.minimumZoomScale {
            let current = max(scrollView.zoomScale, minZoomScale)
            let target = min(
                max(current * adjustedScale, minZoomScale),
                max(scrollView.maximumZoomScale, maxZoomScale)
            )
            scrollView.setZoomScale(target, animated: false)
            gesture.scale = 1
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                snapBackIfNearDefault(scrollView: scrollView)
            }
            return
        }

        // Fallback for preview types that don't expose a zoomable scroll view.
        guard let contentView = preferredContentViewForFallbackZoom() else { return }
        switch gesture.state {
        case .began, .changed:
            let next = min(max(fallbackZoomScale * adjustedScale, minZoomScale), maxZoomScale)
            contentView.transform = CGAffineTransform(scaleX: next, y: next)
            gesture.scale = 1
            fallbackZoomScale = next
        case .ended, .cancelled, .failed:
            if abs(fallbackZoomScale - minZoomScale) <= zoomSnapThreshold {
                fallbackZoomScale = minZoomScale
                UIView.animate(withDuration: 0.15) {
                    contentView.transform = .identity
                }
                return
            }
            fallbackZoomScale = min(max(fallbackZoomScale, minZoomScale), maxZoomScale)
        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let scrollView = findZoomableScrollView(in: view) else {
            guard let contentView = preferredContentViewForFallbackZoom() else { return }
            if fallbackZoomScale > minZoomScale {
                fallbackZoomScale = minZoomScale
                UIView.animate(withDuration: 0.18) {
                    contentView.transform = .identity
                }
            } else {
                fallbackZoomScale = min(doubleTapZoomScale, maxZoomScale)
                UIView.animate(withDuration: 0.18) {
                    contentView.transform = CGAffineTransform(scaleX: self.fallbackZoomScale, y: self.fallbackZoomScale)
                }
            }
            return
        }

        if scrollView.minimumZoomScale >= scrollView.maximumZoomScale {
            scrollView.minimumZoomScale = minZoomScale
            scrollView.maximumZoomScale = maxZoomScale
        }

        if scrollView.zoomScale > minZoomScale {
            scrollView.setZoomScale(minZoomScale, animated: true)
        } else {
            let target = min(doubleTapZoomScale, max(scrollView.maximumZoomScale, maxZoomScale))
            scrollView.setZoomScale(target, animated: true)
        }
    }

    private func snapBackIfNearDefault(scrollView: UIScrollView) {
        if abs(scrollView.zoomScale - minZoomScale) <= zoomSnapThreshold {
            scrollView.setZoomScale(minZoomScale, animated: true)
        }
    }

    private func preferredContentViewForFallbackZoom() -> UIView? {
        // Skip nav bar hierarchy and pick the largest renderable content view.
        let candidates = view.subviews.filter { !$0.isHidden && $0.alpha > 0.01 && !$0.bounds.isEmpty }
        return candidates.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
    }

    private func findZoomableScrollView(in root: UIView) -> UIScrollView? {
        if let scrollView = root as? UIScrollView, scrollView !== view {
            return scrollView
        }
        for child in root.subviews {
            if let found = findZoomableScrollView(in: child) {
                return found
            }
        }
        return nil
    }

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "=", modifierFlags: .command, action: #selector(zoomInCommand), discoverabilityTitle: "Zoom In"),
            UIKeyCommand(input: "-", modifierFlags: .command, action: #selector(zoomOutCommand), discoverabilityTitle: "Zoom Out"),
            UIKeyCommand(input: "0", modifierFlags: .command, action: #selector(resetZoomCommand), discoverabilityTitle: "Actual Size")
        ]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    @objc private func zoomInCommand() {
        applyKeyboardZoom(multiplier: 1.2)
    }

    @objc private func zoomOutCommand() {
        applyKeyboardZoom(multiplier: 0.83)
    }

    @objc private func resetZoomCommand() {
        if let scrollView = findZoomableScrollView(in: view) {
            scrollView.setZoomScale(minZoomScale, animated: true)
        }
        if let contentView = preferredContentViewForFallbackZoom() {
            fallbackZoomScale = minZoomScale
            UIView.animate(withDuration: 0.15) {
                contentView.transform = .identity
            }
        }
    }

    private func applyKeyboardZoom(multiplier: CGFloat) {
        if let scrollView = findZoomableScrollView(in: view) {
            if scrollView.minimumZoomScale >= scrollView.maximumZoomScale {
                scrollView.minimumZoomScale = minZoomScale
                scrollView.maximumZoomScale = maxZoomScale
            }
            let current = max(scrollView.zoomScale, minZoomScale)
            let target = min(max(current * multiplier, minZoomScale), max(scrollView.maximumZoomScale, maxZoomScale))
            scrollView.setZoomScale(target, animated: true)
            return
        }

        guard let contentView = preferredContentViewForFallbackZoom() else { return }
        fallbackZoomScale = min(max(fallbackZoomScale * multiplier, minZoomScale), maxZoomScale)
        UIView.animate(withDuration: 0.15) {
            contentView.transform = CGAffineTransform(scaleX: self.fallbackZoomScale, y: self.fallbackZoomScale)
        }
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
