#if os(macOS)
import SwiftUI
import AppKit
import WebKit

// MARK: - Shared Resources (macOS)

/// Process-level shared expensive WKWebView resources for email rendering on macOS.
///
/// Mirrors the iOS SharedWebViewResources but uses AppKit/NSView.
@MainActor
private enum SharedWebViewResources_macOS {
    static let dataStore: WKWebsiteDataStore = .nonPersistent()

    static let preferences: WKWebpagePreferences = {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        return prefs
    }()
}

/// macOS HTML email renderer using NSViewRepresentable + WKWebView.
///
/// Shares sanitization config with iOS via HTMLSanitizer / TrackingPixelDetector.
/// Only the ViewRepresentable wrapper differs per platform.
///
/// Spec ref: FR-MAC-06 (Email Detail — HTML Rendering)
@MainActor
struct HTMLEmailView_macOS: NSViewRepresentable {

    let htmlContent: String
    var onLinkTapped: ((URL) -> Void)?

    @Binding var contentHeight: CGFloat

    init(
        htmlContent: String,
        contentHeight: Binding<CGFloat>,
        onLinkTapped: ((URL) -> Void)? = nil
    ) {
        self.htmlContent = htmlContent
        self._contentHeight = contentHeight
        self.onLinkTapped = onLinkTapped
    }

    // MARK: - NSViewRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTapped: onLinkTapped, contentHeight: $contentHeight)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = buildWebView(coordinator: context.coordinator)
        context.coordinator.webView = webView
        context.coordinator.lastLoadedHTML = htmlContent
        webView.loadHTMLString(htmlContent, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onLinkTapped = onLinkTapped
        if htmlContent != context.coordinator.lastLoadedHTML {
            context.coordinator.lastLoadedHTML = htmlContent
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }

    // MARK: - Private Helpers

    private func buildWebView(coordinator: Coordinator) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(coordinator, name: "heightChanged")

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = SharedWebViewResources_macOS.preferences
        configuration.websiteDataStore = SharedWebViewResources_macOS.dataStore
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

        var onLinkTapped: ((URL) -> Void)?
        var lastLoadedHTML: String?
        weak var webView: WKWebView?
        private var contentHeight: Binding<CGFloat>

        init(onLinkTapped: ((URL) -> Void)?, contentHeight: Binding<CGFloat>) {
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
                      height > 0 else { return }
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
                guard let url = navigationAction.request.url,
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else { return }

                if let handler = onLinkTapped {
                    handler(url)
                } else {
                    NSWorkspace.shared.open(url)
                }
            default:
                decisionHandler(.allow)
            }
        }

        // MARK: Size-to-Content

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
                var h = measureHeight();
                if (h > 0) {
                    window.webkit.messageHandlers.heightChanged.postMessage(h);
                }
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
