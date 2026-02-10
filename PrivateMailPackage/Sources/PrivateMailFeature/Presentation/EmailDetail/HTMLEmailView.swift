#if os(iOS)
import SwiftUI
import UIKit
import WebKit

// MARK: - Shared Resources

/// Process-level shared expensive WKWebView resources for email rendering.
///
/// Creating a new `.nonPersistent()` data store per WebView is the most
/// expensive part (~15-30ms each). Sharing a single non-persistent store
/// across all email WebViews eliminates this overhead entirely.
///
/// Security: The non-persistent store ensures no cookies/storage persist
/// between app sessions, and the CSP in the HTML blocks external loads.
@MainActor
private enum SharedWebViewResources {
    /// Shared non-persistent data store — the expensive part of WKWebViewConfiguration.
    static let dataStore: WKWebsiteDataStore = .nonPersistent()

    /// Shared webpage preferences (JS enabled for height measurement only).
    static let preferences: WKWebpagePreferences = {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        return prefs
    }()
}

/// A SwiftUI view that safely renders sanitized HTML email content using WKWebView.
///
/// The web view uses a shared non-persistent data store, and intercepts link
/// taps so they open externally rather than navigating in-place.
/// It measures its own content height via a ResizeObserver (with a single
/// fallback measurement) so a parent `ScrollView` can manage scrolling.
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
        context.coordinator.webView = webView
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
        // Per-view configuration — lightweight since it reuses the shared
        // non-persistent data store (the expensive part).
        let contentController = WKUserContentController()
        contentController.add(coordinator, name: "heightChanged")

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = SharedWebViewResources.preferences
        configuration.websiteDataStore = SharedWebViewResources.dataStore
        configuration.userContentController = contentController
        // Suppress data detection (phone, address, etc.) to speed up rendering
        configuration.dataDetectorTypes = []

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
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

        var onLinkTapped: ((URL) -> Void)?
        var lastLoadedHTML: String?
        weak var webView: WKWebView?
        private var contentHeight: Binding<CGFloat>

        init(
            onLinkTapped: ((URL) -> Void)?,
            contentHeight: Binding<CGFloat>
        ) {
            self.onLinkTapped = onLinkTapped
            self.contentHeight = contentHeight
        }

        // MARK: WKScriptMessageHandler

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            Task { @MainActor in
                guard message.name == "heightChanged",
                      let height = message.body as? CGFloat,
                      height > 0 else {
                    return
                }
                let finalHeight = height + 8
                if abs(self.contentHeight.wrappedValue - finalHeight) > 1 {
                    self.contentHeight.wrappedValue = finalHeight
                }
            }
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
            installResizeObserver(webView)
        }

        /// JavaScript that installs a ResizeObserver on the body to notify
        /// us whenever the content height changes, PLUS an immediate measurement.
        ///
        /// This replaces the old 4-pass progressive timer approach:
        /// - ResizeObserver fires immediately on layout and on every reflow
        /// - Handles late image loads, CSS changes, and table rendering
        /// - Single fallback measurement at 500ms for edge cases
        private func installResizeObserver(_ webView: WKWebView) {
            let observerJS = """
            (function() {
                function measureHeight() {
                    var body = document.body;
                    var html = document.documentElement;
                    return Math.max(
                        body.scrollHeight, body.offsetHeight, body.clientHeight,
                        html.scrollHeight, html.offsetHeight, html.clientHeight
                    );
                }

                // Send initial measurement immediately
                var h = measureHeight();
                if (h > 0) {
                    window.webkit.messageHandlers.heightChanged.postMessage(h);
                }

                // Install ResizeObserver for ongoing layout changes
                if (typeof ResizeObserver !== 'undefined') {
                    var lastHeight = h;
                    var observer = new ResizeObserver(function() {
                        var newH = measureHeight();
                        if (newH > 0 && Math.abs(newH - lastHeight) > 1) {
                            lastHeight = newH;
                            window.webkit.messageHandlers.heightChanged.postMessage(newH);
                        }
                    });
                    observer.observe(document.body);
                }

                // Single fallback at 500ms for edge cases (complex table layouts)
                setTimeout(function() {
                    var finalH = measureHeight();
                    if (finalH > 0) {
                        window.webkit.messageHandlers.heightChanged.postMessage(finalH);
                    }
                }, 500);
            })()
            """

            webView.evaluateJavaScript(observerJS) { _, _ in }
        }
    }
}
#endif
