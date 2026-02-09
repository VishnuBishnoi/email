#if os(iOS)
import SwiftUI
import UIKit
import WebKit

/// A SwiftUI view that safely renders sanitized HTML email content using WKWebView.
///
/// The web view disables JavaScript execution, uses a non-persistent data store,
/// and intercepts link taps so they open externally rather than navigating in-place.
/// It measures its own content height after load so a parent `ScrollView` can
/// manage scrolling.
@MainActor
struct HTMLEmailView: UIViewRepresentable {

    /// Sanitized HTML body to render.
    let htmlContent: String

    /// Base font size in points applied via Dynamic Type CSS injection.
    var fontSizePoints: CGFloat = 16

    /// Called when the user taps a link inside the email body.
    /// If `nil`, links open in Safari via `UIApplication.shared.open`.
    var onLinkTapped: ((URL) -> Void)?

    // MARK: - Content Height Binding

    /// Tracks the rendered content height so the parent can size the view.
    @Binding var contentHeight: CGFloat

    // MARK: - Initialiser

    init(
        htmlContent: String,
        fontSizePoints: CGFloat = 16,
        contentHeight: Binding<CGFloat>,
        onLinkTapped: ((URL) -> Void)? = nil
    ) {
        self.htmlContent = htmlContent
        self.fontSizePoints = fontSizePoints
        self._contentHeight = contentHeight
        self.onLinkTapped = onLinkTapped
    }

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTapped: onLinkTapped, contentHeight: $contentHeight)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = buildWebView(coordinator: context.coordinator)
        let styledHTML = HTMLSanitizer.injectDynamicTypeCSS(
            htmlContent,
            fontSizePoints: fontSizePoints
        )
        context.coordinator.lastLoadedHTML = styledHTML
        webView.loadHTMLString(styledHTML, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLinkTapped = onLinkTapped
        // Only reload if the HTML content actually changed (M2 fix: avoid
        // unnecessary WKWebView reloads on every SwiftUI re-render).
        let styledHTML = HTMLSanitizer.injectDynamicTypeCSS(
            htmlContent,
            fontSizePoints: fontSizePoints
        )
        if styledHTML != context.coordinator.lastLoadedHTML {
            context.coordinator.lastLoadedHTML = styledHTML
            webView.loadHTMLString(styledHTML, baseURL: nil)
        }
    }

    // MARK: - Private Helpers

    private func buildWebView(coordinator: Coordinator) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = preferences
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.accessibilityLabel = NSLocalizedString(
            "Email body content",
            comment: "Accessibility label for the HTML email body web view"
        )

        return webView
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {

        var onLinkTapped: ((URL) -> Void)?
        var lastLoadedHTML: String?
        private var contentHeight: Binding<CGFloat>

        init(
            onLinkTapped: ((URL) -> Void)?,
            contentHeight: Binding<CGFloat>
        ) {
            self.onLinkTapped = onLinkTapped
            self.contentHeight = contentHeight
        }

        // MARK: Navigation Policy

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            switch navigationAction.navigationType {
            case .linkActivated:
                decisionHandler(.cancel)
                guard let url = navigationAction.request.url else { return }

                // PR #8 Comment 4: Only allow http/https links to open externally.
                guard let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else {
                    return
                }

                if let handler = onLinkTapped {
                    handler(url)
                } else {
                    UIApplication.shared.open(url)
                }
            default:
                decisionHandler(.allow)
            }
        }

        // MARK: Size-to-Content

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let height = webView.scrollView.contentSize.height
            guard height > 0 else { return }
            contentHeight.wrappedValue = height
        }
    }
}
#endif
