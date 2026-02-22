import SwiftUI

/// A single thread row in the thread list.
/// Pure view component -- receives thread data, performs no fetching.
///
/// Layout (HStack):
///  1. Optional checkbox (multi-select mode)
///  2. Unread indicator dot (leading edge)
///  3. AvatarView (participants + optional account color)
///  4. Content VStack:
///     - Row 1: sender name(s) + count  |  timestamp
///     - Row 2: subject  |  star icon
///     - Row 3: snippet  |  attachment icon + category badge
///
/// Spec ref: Thread List spec FR-TL-01, NFR-TL-03
struct ThreadRowView: View {
    let thread: VaultMailFeature.Thread
    var isMultiSelectMode: Bool = false
    var isSelected: Bool = false
    var accountColor: Color? = nil
    var isMuted: Bool = false

    @Environment(ThemeProvider.self) private var theme

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

    /// Whether any email in the thread is flagged as spam/phishing.
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
        .padding(.vertical, theme.spacing.listRowVertical)
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
        VStack(alignment: .leading, spacing: theme.spacing.xxs + 1) {
            senderRow
            subjectRow
            snippetRow
        }
    }

    // Row 1: sender + timestamp
    private var senderRow: some View {
        HStack {
            Text(senderText)
                .font(isUnread ? theme.typography.titleSmall : theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(timestampText)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
        }
    }

    // Row 2: subject + star
    private var subjectRow: some View {
        HStack {
            Text(thread.subject)
                .font(isUnread ? theme.typography.bodyMediumEmphasized : theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textPrimary)
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

    // Row 3: snippet + spam indicator + attachment + category
    private var snippetRow: some View {
        HStack {
            if isSpam {
                Label("Spam", systemImage: "exclamationmark.shield.fill")
                    .font(theme.typography.labelSmall)
                    .bold()
                    .foregroundStyle(theme.colors.textInverse)
                    .padding(.horizontal, theme.spacing.chipHorizontal / 2)
                    .padding(.vertical, theme.spacing.xxs)
                    .background(theme.colors.destructive, in: RoundedRectangle(cornerRadius: 4))
                    .accessibilityLabel("Flagged as spam")
            }

            if isMuted {
                Image(systemName: "bell.slash")
                    .font(theme.typography.labelSmall)
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityLabel("Muted")
            }

            Text(thread.snippet ?? "")
                .font(theme.typography.bodySmall)
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)

            Spacer()

            if hasAttachments {
                Image(systemName: "paperclip")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .accessibilityHidden(true)
            }

            CategoryBadgeView(category: category)
        }
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

        if isMuted {
            parts.append("Muted")
        }

        if let category, category != .uncategorized {
            parts.append("\(category.displayLabel) category")
        }

        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

#Preview("Unread Thread") {
    let thread = VaultMailFeature.Thread(
        accountId: "acc-1",
        subject: "Quarterly Report Review",
        latestDate: Date(),
        messageCount: 3,
        unreadCount: 2,
        isStarred: false,
        aiCategory: AICategory.updates.rawValue,
        snippet: "Please review the attached quarterly report and provide feedback by Friday.",
        participants: Participant.encode([
            Participant(name: "Alice Johnson", email: "alice@company.com"),
            Participant(name: "Bob Smith", email: "bob@company.com"),
            Participant(name: "Carol White", email: "carol@company.com")
        ])
    )
    return List {
        ThreadRowView(thread: thread)
    }
    .listStyle(.plain)
    .environment(ThemeProvider())
}

#Preview("Read + Starred") {
    let thread = VaultMailFeature.Thread(
        accountId: "acc-1",
        subject: "Weekend Plans",
        latestDate: Calendar.current.date(byAdding: .day, value: -1, to: .now),
        messageCount: 5,
        unreadCount: 0,
        isStarred: true,
        aiCategory: AICategory.social.rawValue,
        snippet: "Hey! Are we still on for Saturday brunch?",
        participants: Participant.encode([
            Participant(name: "Sarah Miller", email: "sarah@email.com")
        ])
    )
    return List {
        ThreadRowView(thread: thread)
    }
    .listStyle(.plain)
    .environment(ThemeProvider())
}

#Preview("Multi-Select Mode") {
    let thread = VaultMailFeature.Thread(
        accountId: "acc-1",
        subject: "Your order has shipped!",
        latestDate: Calendar.current.date(byAdding: .day, value: -3, to: .now),
        messageCount: 1,
        unreadCount: 1,
        aiCategory: AICategory.promotions.rawValue,
        snippet: "Your package is on its way. Track your order for delivery updates.",
        participants: Participant.encode([
            Participant(name: nil, email: "orders@store.com")
        ])
    )
    return List {
        ThreadRowView(thread: thread, isMultiSelectMode: true, isSelected: true)
        ThreadRowView(thread: thread, isMultiSelectMode: true, isSelected: false)
    }
    .listStyle(.plain)
    .environment(ThemeProvider())
}

#Preview("With Account Color") {
    let thread = VaultMailFeature.Thread(
        accountId: "acc-2",
        subject: "Meeting Notes",
        latestDate: Date(),
        messageCount: 1,
        unreadCount: 0,
        snippet: "Here are the notes from today's standup meeting.",
        participants: Participant.encode([
            Participant(name: "Team Lead", email: "lead@work.com")
        ])
    )
    return List {
        ThreadRowView(thread: thread, accountColor: .orange)
    }
    .listStyle(.plain)
    .environment(ThemeProvider())
}

#Preview("No Category, No Snippet") {
    let thread = VaultMailFeature.Thread(
        accountId: "acc-1",
        subject: "Welcome to our forum!",
        latestDate: Calendar.current.date(byAdding: .month, value: -2, to: .now),
        messageCount: 1,
        unreadCount: 1,
        isStarred: false,
        aiCategory: AICategory.forums.rawValue,
        participants: Participant.encode([
            Participant(name: "Forum Bot", email: "noreply@forum.dev")
        ])
    )
    return List {
        ThreadRowView(thread: thread)
    }
    .listStyle(.plain)
    .environment(ThemeProvider())
}
