import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A single email message "bubble" within the thread detail.
///
/// Supports two modes:
/// - **Collapsed**: sender name, timestamp, and snippet (tap to expand)
/// - **Expanded**: full header, sanitized HTML/plain body, quoted text expander,
///   attachment list, and tracker badge
///
/// Spec ref: FR-ED-01 (expand/collapse), FR-ED-04 (HTML safety),
///           FR-ED-03 (attachments), AC-U-09 (trackers)
struct MessageBubbleView: View {

    // MARK: - Properties

    let email: Email
    let isExpanded: Bool
    let isTrustedSender: Bool
    let onToggleExpand: () -> Void
    let onStarToggle: () -> Void
    let onPreviewAttachment: (Attachment) -> Void
    let onShareAttachment: (URL) -> Void
    let onAlwaysLoadImages: () -> Void
    let downloadUseCase: DownloadAttachmentUseCaseProtocol

    // MARK: - Local State

    @State private var loadRemoteImages = false
    @State private var showQuotedText = false
    @State private var trackerCount = 0
    @State private var processedHTML: String?
    @State private var hasQuotedText = false
    @State private var hasBlockedRemoteContent = false
    @State private var remoteImageCount = 0
    @State private var htmlContentHeight: CGFloat = 44

    /// Intermediate cache: sanitized + tracking-stripped + quoted-text-detected HTML.
    /// This avoids re-running the expensive 20+ regex pipeline when only
    /// `showQuotedText` or `dynamicTypeSize` changes.
    @State private var baseProcessedHTML: String?
    /// Cache key tracking which email + remote-image state produced `baseProcessedHTML`.
    @State private var baseCacheKey: String?

    // MARK: - Environment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .accessibilityElement(children: isExpanded ? .contain : .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            onToggleExpand()
        }
        .accessibilityAction(named: "Star") {
            onStarToggle()
        }
        .accessibilityAction(named: "Reply") {
            // TODO: Navigate to composer — wired when Email Composer feature is built
        }
        .accessibilityIdentifier("message-bubble-\(email.id)")
    }

    // MARK: - Collapsed

    private var collapsedContent: some View {
        Button(action: onToggleExpand) {
            HStack(spacing: 10) {
                avatarView(size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(senderDisplayName)
                            .font(.subheadline)
                            .fontWeight(email.isRead ? .regular : .semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Text(formattedDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(email.snippet ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            MessageHeaderView(
                email: email,
                isExpanded: true,
                onStarToggle: onStarToggle
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // Remote content banner
            if hasBlockedRemoteContent && !loadRemoteImages {
                remoteContentBanner
                    .padding(.horizontal, 12)
            }

            // Tracker badge
            if trackerCount > 0 {
                trackerBadge
                    .padding(.horizontal, 12)
            }

            // Body content — minimal horizontal padding so HTML renders
            // closer to edge-to-edge within the bubble card.
            bodyContent
                .padding(.horizontal, 4)

            // Quoted text expander
            if hasQuotedText && !showQuotedText {
                quotedTextButton
                    .padding(.horizontal, 12)
            }

            // Attachments
            if !email.attachments.isEmpty {
                attachmentSection
                    .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 12)
        .task(id: "\(email.id)-\(loadRemoteImages)-\(showQuotedText)-\(dynamicTypeSize)") {
            await processEmailBody()
        }
    }

    // MARK: - Body Content

    @ViewBuilder
    private var bodyContent: some View {
        #if os(iOS)
        if let html = processedHTML, !html.isEmpty {
            HTMLEmailView(
                htmlContent: html,
                contentHeight: $htmlContentHeight,
                onLinkTapped: { url in
                    // PR #8 Comment 4: Only allow http/https links.
                    guard let scheme = url.scheme?.lowercased(),
                          scheme == "http" || scheme == "https" else { return }
                    UIApplication.shared.open(url)
                }
            )
            .frame(height: max(htmlContentHeight, 44))
            .clipped()
            .animation(.easeInOut(duration: 0.15), value: htmlContentHeight)
        } else if let plainText = email.bodyPlain, !plainText.isEmpty {
            Text(MIMEDecoder.stripMIMEFraming(HTMLSanitizer.stripIMAPFraming(plainText)))
                .font(.body)
                .textSelection(.enabled)
        } else {
            noContentPlaceholder
        }
        #else
        if let plainText = email.bodyPlain, !plainText.isEmpty {
            Text(MIMEDecoder.stripMIMEFraming(HTMLSanitizer.stripIMAPFraming(plainText)))
                .font(.body)
                .textSelection(.enabled)
        } else if let html = processedHTML, !html.isEmpty {
            // TODO: [P2] macOS HTML rendering gap — spec requires WKWebView on macOS too.
            // Current fallback strips HTML to plain text. When macOS is a supported
            // platform, implement NSViewRepresentable wrapping WKWebView similar to
            // HTMLEmailView (iOS). Tracked by PR #8 Comment 6.
            Text(Self.stripHTMLTags(from: html))
                .font(.body)
                .textSelection(.enabled)
        } else {
            noContentPlaceholder
        }
        #endif
    }

    private var noContentPlaceholder: some View {
        Text("No content")
            .font(.body)
            .foregroundStyle(.secondary)
            .italic()
    }

    // MARK: - Remote Content Banner

    private var remoteContentBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(.secondary)

            Text("\(remoteImageCount) remote image\(remoteImageCount == 1 ? "" : "s") blocked")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Load Images") {
                withAnimation(.easeIn(duration: 0.2)) {
                    loadRemoteImages = true
                }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.mini)

            if !isTrustedSender {
                Button("Always Load") {
                    onAlwaysLoadImages()
                    loadRemoteImages = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(8)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Remote images blocked. \(remoteImageCount) images.")
    }

    // MARK: - Tracker Badge

    private var trackerBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "shield.checkmark.fill")
                .foregroundStyle(.green)
                .font(.caption2)
            Text("\(trackerCount) tracker\(trackerCount == 1 ? "" : "s") blocked")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trackerCount) tracking pixels blocked")
    }

    // MARK: - Quoted Text Button

    private var quotedTextButton: some View {
        Button {
            let animation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.25)
            withAnimation(animation) {
                showQuotedText = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "ellipsis")
                Text("Show quoted text")
                    .font(.caption)
            }
            .foregroundStyle(.blue)
        }
        .accessibilityLabel("Show quoted text from previous messages")
    }

    // MARK: - Attachments

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            ForEach(email.attachments, id: \.id) { attachment in
                AttachmentRowView(
                    attachment: attachment,
                    downloadUseCase: downloadUseCase,
                    onPreview: onPreviewAttachment,
                    onShare: onShareAttachment
                )
            }
        }
    }

    // MARK: - Processing

    private func processEmailBody() async {
        let shouldLoadRemote = loadRemoteImages || isTrustedSender

        // Reset height so the WebView remeasures fresh content
        htmlContentHeight = 44

        // Cache key for the expensive steps (sanitize + tracking + quoted detection).
        // Only re-run these when the email content or remote-image preference changes.
        // Quoted text toggle and Dynamic Type changes only need the cheap CSS step.
        let currentCacheKey = "\(email.id)-\(shouldLoadRemote)"

        if baseCacheKey != currentCacheKey {
            // Cache miss — run the full expensive pipeline

            // Determine HTML source: prefer bodyHTML, but also check bodyPlain
            // for raw MIME multipart content that may contain an HTML part
            // (happens when BODYSTRUCTURE parsing failed during sync).
            var htmlSource = email.bodyHTML

            if (htmlSource == nil || htmlSource?.isEmpty == true),
               let plainBody = email.bodyPlain,
               MIMEDecoder.isMultipartContent(plainBody),
               let multipart = MIMEDecoder.parseMultipartBody(plainBody),
               let mimeHTML = multipart.htmlText, !mimeHTML.isEmpty {
                htmlSource = mimeHTML
            }

            guard let htmlBody = htmlSource, !htmlBody.isEmpty else {
                processedHTML = nil
                baseProcessedHTML = nil
                baseCacheKey = nil
                hasBlockedRemoteContent = false
                remoteImageCount = 0
                trackerCount = 0
                hasQuotedText = false
                return
            }

            // Step 1: Sanitize (uses HTMLSanitizer's own internal cache)
            let sanitized = HTMLSanitizer.sanitize(
                htmlBody,
                loadRemoteImages: shouldLoadRemote
            )
            hasBlockedRemoteContent = sanitized.hasBlockedRemoteContent
            remoteImageCount = sanitized.remoteImageCount

            // Step 2: Strip tracking pixels (always, even with remote images loaded)
            let tracked = TrackingPixelDetector.detect(in: sanitized.html)
            trackerCount = tracked.trackerCount

            // Step 3: Detect quoted text
            let quoted = QuotedTextDetector.detectInHTML(tracked.sanitizedHTML)
            hasQuotedText = quoted.hasQuotedText

            // Cache the base result — quoted text CSS & Dynamic Type are cheap to apply
            baseProcessedHTML = quoted.processedHTML
            baseCacheKey = currentCacheKey
        }

        // Steps 4–5 run on every call (cheap string operations)
        guard let base = baseProcessedHTML else {
            processedHTML = nil
            return
        }

        // Step 4: Apply quoted text visibility via CSS
        var finalHTML = base
        if !showQuotedText && hasQuotedText {
            finalHTML = """
            <style>.pm-quoted-text { display: none; } .pm-quote-toggle { display: none; }</style>
            \(finalHTML)
            """
        }

        // Step 5: Inject Dynamic Type CSS
        #if os(iOS)
        let fontSize = UIFont.preferredFont(forTextStyle: .body).pointSize
        #else
        let fontSize: CGFloat = 16
        #endif
        processedHTML = HTMLSanitizer.injectDynamicTypeCSS(
            finalHTML,
            fontSizePoints: fontSize,
            allowRemoteImages: loadRemoteImages || isTrustedSender
        )
    }

    // MARK: - Helpers

    private var senderDisplayName: String {
        if let name = email.fromName, !name.isEmpty {
            return name
        }
        return email.fromAddress.components(separatedBy: "@").first ?? email.fromAddress
    }

    private var formattedDate: String {
        (email.dateReceived ?? email.dateSent)?.relativeThreadFormat() ?? ""
    }

    private func avatarView(size: CGFloat) -> some View {
        let initial = String(senderDisplayName.prefix(1)).uppercased()
        let color = avatarColor(for: email.fromAddress)

        return Text(initial)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    private func avatarColor(for email: String) -> Color {
        let colors: [Color] = [
            .blue, .green, .orange, .purple, .pink,
            .red, .teal, .indigo, .cyan, .mint
        ]
        let hash = abs(email.hashValue)
        return colors[hash % colors.count]
    }

    /// Strip HTML tags to produce a plain-text fallback (used on macOS where
    /// WKWebView is not yet wired). Replaces block-level closing tags with
    /// newlines so the output preserves paragraph structure.
    static func stripHTMLTags(from html: String) -> String {
        var result = html
        // Replace <br>, </p>, </div>, </li> with newlines for readability
        result = result.replacingOccurrences(
            of: "<br\\s*/?>|</p>|</div>|</li>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        // Strip remaining tags
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        // Decode common HTML entities
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        // Collapse multiple blank lines
        result = result.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var accessibilityDescription: String {
        let status = email.isRead ? "Read" : "Unread"
        let star = email.isStarred ? ", Starred" : ""
        return "\(status) message from \(senderDisplayName), \(formattedDate)\(star)"
    }
}

// MARK: - Preview Helper

@MainActor
private final class PreviewBubbleDownloadUseCase: DownloadAttachmentUseCaseProtocol {
    func download(attachment: Attachment) async throws -> String {
        try await Task.sleep(for: .seconds(1))
        return NSTemporaryDirectory() + attachment.filename
    }
    func securityWarning(for filename: String) -> String? { nil }
    func requiresCellularWarning(sizeBytes: Int) -> Bool { false }
}

// MARK: - Previews

#Preview("Collapsed") {
    let email = Email(
        accountId: "acc-1",
        threadId: "thread-1",
        messageId: "msg-1",
        fromAddress: "alice@example.com",
        fromName: "Alice Johnson",
        toAddresses: Participant.encode([
            Participant(name: "Bob Smith", email: "bob@example.com")
        ]),
        subject: "Project Update",
        snippet: "Hey Bob, just wanted to share the latest progress on the...",
        dateReceived: Date(),
        isRead: true,
        isStarred: false
    )

    MessageBubbleView(
        email: email,
        isExpanded: false,
        isTrustedSender: false,
        onToggleExpand: {},
        onStarToggle: {},
        onPreviewAttachment: { _ in },
        onShareAttachment: { _ in },
        onAlwaysLoadImages: {},
        downloadUseCase: PreviewBubbleDownloadUseCase()
    )
    .padding()
}

#Preview("Expanded - Plain Text") {
    let email = Email(
        accountId: "acc-1",
        threadId: "thread-1",
        messageId: "msg-2",
        fromAddress: "carol@company.com",
        fromName: "Carol White",
        toAddresses: Participant.encode([
            Participant(name: "Alice Johnson", email: "alice@example.com")
        ]),
        subject: "Meeting Notes",
        bodyPlain: "Hi Alice,\n\nHere are the notes from today's meeting:\n\n1. Budget approved\n2. Timeline confirmed for Q3\n3. New hire starts Monday\n\nBest,\nCarol",
        dateReceived: Calendar.current.date(byAdding: .hour, value: -2, to: .now),
        isRead: false,
        isStarred: true
    )

    ScrollView {
        MessageBubbleView(
            email: email,
            isExpanded: true,
            isTrustedSender: false,
            onToggleExpand: {},
            onStarToggle: {},
            onPreviewAttachment: { _ in },
            onShareAttachment: { _ in },
            onAlwaysLoadImages: {},
            downloadUseCase: PreviewBubbleDownloadUseCase()
        )
        .padding()
    }
}
