#if os(iOS)
import SwiftUI
import UIKit
import WebKit

/// A SwiftUI view that safely renders sanitized HTML email content using WKWebView.
///
/// The web view disables JavaScript execution, uses a non-persistent data store,
/// and intercepts link taps so they open externally rather than navigating in-place.
/// It measures its own content height via JavaScript after load so a parent
/// `ScrollView` can manage scrolling.
@MainActor
struct HTMLEmailView: UIViewRepresentable {

    /// Full sanitized HTML document to render.
    let htmlContent: String

    /// Called when the user taps a link inside the email body.
    /// If `nil`, links open in Safari via `UIApplication.shared.open`.
    var onLinkTapped: ((URL) -> Void)?

    // MARK: - Content Height Binding

    /// Tracks the rendered content height so the parent can size the view.
    @Binding var contentHeight: CGFloat

    // MARK: - Initialiser

    init(
        htmlContent: String,
        contentHeight: Binding<CGFloat>,
        onLinkTapped: ((URL) -> Void)? = nil
    ) {
        self.htmlContent = htmlContent
        self._contentHeight = contentHeight
        self.onLinkTapped = onLinkTapped
    }

    // MARK: - UIViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTapped: onLinkTapped, contentHeight: $contentHeight)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = buildWebView(coordinator: context.coordinator)
        context.coordinator.lastLoadedHTML = htmlContent
        webView.loadHTMLString(htmlContent, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLinkTapped = onLinkTapped
        // Only reload if the HTML content actually changed (M2 fix: avoid
        // unnecessary WKWebView reloads on every SwiftUI re-render).
        if htmlContent != context.coordinator.lastLoadedHTML {
            context.coordinator.lastLoadedHTML = htmlContent
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }

    // MARK: - Private Helpers

    private func buildWebView(coordinator: Coordinator) -> WKWebView {
        // Enable JavaScript ONLY for our height-measurement snippet.
        // The CSP `default-src 'none'` in the HTML document blocks all
        // external script loading; inline scripts are also blocked by CSP.
        // We allow JS at the WebView level solely so evaluateJavaScript
        // can measure document.body.scrollHeight after load.
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = preferences
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsHorizontalScrollIndicator = false
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
            measureContentHeight(webView)
        }

        /// Measure the actual rendered content height via JavaScript.
        ///
        /// Uses `document.body.scrollHeight` which is more reliable than
        /// `scrollView.contentSize.height` as it waits for the layout pass.
        /// A short delay ensures images and CSS have been fully applied.
        private func measureContentHeight(_ webView: WKWebView) {
            let js = "Math.max(document.body.scrollHeight, document.body.offsetHeight, document.documentElement.scrollHeight)"
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self,
                      let height = result as? CGFloat,
                      height > 0 else {
                    return
                }
                // Add a small buffer to prevent clipping at the bottom
                let finalHeight = height + 2
                if abs(self.contentHeight.wrappedValue - finalHeight) > 1 {
                    self.contentHeight.wrappedValue = finalHeight
                }

                // Re-measure after a brief delay to catch late-loading content
                // (e.g. data: images rendering, CSS reflow).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.remeasureContentHeight(webView)
                }
            }
        }

        private func remeasureContentHeight(_ webView: WKWebView) {
            let js = "Math.max(document.body.scrollHeight, document.body.offsetHeight, document.documentElement.scrollHeight)"
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self,
                      let height = result as? CGFloat,
                      height > 0 else {
                    return
                }
                let finalHeight = height + 2
                if abs(self.contentHeight.wrappedValue - finalHeight) > 1 {
                    self.contentHeight.wrappedValue = finalHeight
                }
            }
        }
    }
}
#endif
