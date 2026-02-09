#if os(iOS)
import QuickLook
import SwiftUI

/// Wraps `QLPreviewController` for previewing downloaded attachment files.
///
/// Uses `UIViewControllerRepresentable` to bridge UIKit's QuickLook into SwiftUI.
/// Supports any file type that QuickLook can render (PDF, images, text, etc.).
///
/// Spec ref: Email Detail FR-ED-03
struct AttachmentPreviewView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> any QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - Previews

#Preview("PDF Preview") {
    AttachmentPreviewView(
        url: URL(fileURLWithPath: "/tmp/sample.pdf")
    )
}
#endif
