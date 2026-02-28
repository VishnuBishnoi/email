import SwiftUI

/// A thread row variant that highlights matching search terms in subject and snippet.
///
/// Uses the same layout and styling as `ThreadRowView` but replaces the plain
/// subject and snippet text with attributed strings that bold-highlight the
/// query terms. FTS5's `highlight()` wraps matched terms in `<b>...</b>` tags
/// which this view parses into bold text spans.
///
/// Spec ref: FR-SEARCH-03, AC-S-04 (highlight matching terms)
struct HighlightedThreadRowView: View {
    @Environment(ThemeProvider.self) private var theme
    let thread: VaultMailFeature.Thread
    let highlightedSubject: String
    let highlightedSnippet: String
    let queryText: String
    var isMultiSelectMode: Bool = false
    var isSelected: Bool = false
    var accountColor: Color? = nil

    // MARK: - Derived State

    private var participants: [Participant] {
        Participant.decode(from: thread.participants)
    }

    private var isUnread: Bool {
        thread.unreadCount > 0
    }

    private var hasAttachments: Bool {
        thread.emails.contains { !$0.attachments.isEmpty }
    }

    private var isSpam: Bool {
        thread.emails.contains { $0.isSpam }
    }

    private var category: AICategory? {
        guard let raw = thread.aiCategory else { return nil }
        return AICategory(rawValue: raw)
    }

    private var senderText: String {
        guard !participants.isEmpty else { return "Unknown" }
        let names: String
        if participants.count >= 2 {
            names = "\(participants[0].displayName), \(participants[1].displayName)"
        } else {
            names = participants[0].displayName
        }
        if thread.messageCount > 1 {
            return "\(names) (\(thread.messageCount))"
        }
        return names
    }

    private var timestampText: String {
        thread.latestDate?.relativeThreadFormat() ?? ""
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.listRowSpacing) {
            if isMultiSelectMode {
                selectCheckbox
            }

            unreadDot

            AvatarView(
                participants: participants,
                accountColor: accountColor
            )

            contentStack
        }
        .padding(.vertical, theme.spacing.chipVertical)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Checkbox

    private var selectCheckbox: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(theme.typography.titleLarge)
            .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.textSecondary)
            .accessibilityLabel(isSelected ? "Selected" : "Not selected")
    }

    // MARK: - Unread Dot

    private var unreadDot: some View {
        Circle()
            .fill(isUnread ? theme.colors.unreadDot : Color.clear)
            .frame(width: 6, height: 6)
            .padding(.top, theme.spacing.sm)
            .accessibilityHidden(true)
    }

    // MARK: - Content Stack

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            senderRow
            subjectRow
            snippetRow
        }
    }

    // Row 1: sender + timestamp
    private var senderRow: some View {
        HStack {
            Text(senderText)
                .font(theme.typography.bodyMedium)
                .fontWeight(isUnread ? .bold : .regular)
                .lineLimit(1)

            Spacer()

            Text(timestampText)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    // Row 2: subject with highlights + star
    private var subjectRow: some View {
        HStack {
            highlightedText(highlightedSubject, fallback: thread.subject)
                .font(theme.typography.bodyMedium)
                .fontWeight(isUnread ? .semibold : .regular)
                .lineLimit(1)

            Spacer()

            if thread.isStarred {
                Image(systemName: "star.fill")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.starred)
                    .accessibilityHidden(true)
            }
        }
    }

    // Row 3: snippet with highlights + spam indicator + attachment + category
    private var snippetRow: some View {
        HStack {
            if isSpam {
                Label("Spam", systemImage: "exclamationmark.shield.fill")
                    .font(theme.typography.labelSmall.bold())
                    .foregroundStyle(theme.colors.textInverse)
                    .padding(.horizontal, theme.spacing.chipVertical)
                    .padding(.vertical, theme.spacing.xxs)
                    .background(theme.colors.destructive, in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel("Flagged as spam")
            }

            highlightedText(highlightedSnippet, fallback: thread.snippet ?? "")
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)

            Spacer()

            if hasAttachments {
                Image(systemName: "paperclip")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityHidden(true)
            }

            CategoryBadgeView(category: category)
        }
    }

    // MARK: - Highlight Parsing

    /// Parses FTS5 `<b>...</b>` highlight markers into an AttributedString with
    /// bold+tinted spans. Falls back to plain text if no markers are present.
    @ViewBuilder
    private func highlightedText(_ highlighted: String, fallback: String) -> some View {
        if highlighted.contains("<b>") {
            Text(parseHighlightedAttributedString(highlighted))
        } else {
            // Fallback: manually highlight query terms
            Text(manualHighlight(text: fallback, query: queryText))
        }
    }

    /// Parse `<b>matched</b>` markers from FTS5 highlight() into AttributedString.
    private func parseHighlightedAttributedString(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text[...]

        while let openRange = remaining.range(of: "<b>") {
            // Append text before the tag
            let before = String(remaining[remaining.startIndex..<openRange.lowerBound])
            result.append(AttributedString(before))

            remaining = remaining[openRange.upperBound...]

            if let closeRange = remaining.range(of: "</b>") {
                // Append highlighted text
                let matchedText = String(remaining[remaining.startIndex..<closeRange.lowerBound])
                var highlighted = AttributedString(matchedText)
                highlighted.font = theme.typography.bodyMedium.bold()
                highlighted.foregroundColor = theme.colors.accent
                result.append(highlighted)
                remaining = remaining[closeRange.upperBound...]
            } else {
                // No closing tag, append rest as-is
                result.append(AttributedString(String(remaining)))
                remaining = remaining[remaining.endIndex...]
            }
        }

        // Append any remaining text
        if !remaining.isEmpty {
            result.append(AttributedString(String(remaining)))
        }

        return result
    }

    /// Manual keyword highlighting when FTS5 highlight data isn't available.
    private func manualHighlight(text: String, query: String) -> AttributedString {
        guard !query.isEmpty, !text.isEmpty else {
            return AttributedString(text)
        }

        var result = AttributedString(text)
        let queryWords = query.lowercased().split(separator: " ")

        for word in queryWords {
            var searchRange = result.startIndex..<result.endIndex
            while let range = result[searchRange].range(of: String(word), options: .caseInsensitive) {
                result[range].font = theme.typography.bodyMedium.bold()
                result[range].foregroundColor = theme.colors.accent
                if range.upperBound < result.endIndex {
                    searchRange = range.upperBound..<result.endIndex
                } else {
                    break
                }
            }
        }

        return result
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts: [String] = []
        parts.append("From \(senderText)")
        parts.append(thread.subject)
        if let snippet = thread.snippet, !snippet.isEmpty {
            parts.append(snippet)
        }
        if !timestampText.isEmpty {
            parts.append(timestampText)
        }
        parts.append(isUnread ? "Unread" : "Read")
        if thread.isStarred {
            parts.append("Starred")
        }
        if hasAttachments {
            parts.append("Has attachments")
        }
        if let category, category != .uncategorized {
            parts.append("\(category.displayLabel) category")
        }
        return parts.joined(separator: ", ")
    }
}
