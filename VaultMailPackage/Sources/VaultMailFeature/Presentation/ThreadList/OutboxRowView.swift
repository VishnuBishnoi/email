import SwiftUI

/// A specialized row view for displaying outbox emails with send state indicators.
///
/// Shows the send pipeline state (queued, sending, failed) with appropriate icons,
/// recipient info, subject, snippet, and contextual action buttons for retry/cancel.
///
/// Spec ref: Thread List spec FR-TL-07 (Outbox display)
struct OutboxRowView: View {
    let email: Email
    let onRetry: () -> Void
    let onCancel: () -> Void

    @Environment(ThemeProvider.self) private var theme

    // MARK: - Derived State

    private var sendState: SendState {
        SendState(rawValue: email.sendState) ?? .none
    }

    private var recipientDisplay: String {
        parseFirstRecipient(from: email.toAddresses)
    }

    private var timestampText: String {
        if let date = email.sendQueuedDate ?? email.dateReceived {
            return date.relativeThreadFormat()
        }
        return ""
    }

    private var subjectIsBold: Bool {
        sendState == .queued || sendState == .sending
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.listRowSpacing) {
            sendStateIndicator
            contentStack
            Spacer()
            actionButton
        }
        .padding(.vertical, theme.spacing.listRowVertical)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Send State Indicator

    @ViewBuilder
    private var sendStateIndicator: some View {
        switch sendState {
        case .queued:
            Image(systemName: "clock")
                .font(theme.typography.bodyLarge)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        case .sending:
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(theme.typography.bodyLarge)
                .foregroundStyle(theme.colors.destructive)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        case .none, .sent:
            Image(systemName: "paperplane")
                .font(theme.typography.bodyLarge)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Content Stack

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: theme.spacing.xxs + 1) {
            recipientRow
            subjectRow
            snippetRow
            sendStateLabel
        }
    }

    /// Row 1: recipient + date
    private var recipientRow: some View {
        HStack {
            Text(recipientDisplay)
                .font(subjectIsBold ? theme.typography.titleSmall : theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(timestampText)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
        }
    }

    /// Row 2: subject
    private var subjectRow: some View {
        Text(email.subject)
            .font(subjectIsBold ? theme.typography.bodyMediumEmphasized : theme.typography.bodyMedium)
            .foregroundStyle(theme.colors.textPrimary)
            .lineLimit(1)
    }

    /// Row 3: snippet
    private var snippetRow: some View {
        Text(email.snippet ?? "")
            .font(theme.typography.bodySmall)
            .foregroundStyle(theme.colors.textTertiary)
            .lineLimit(1)
    }

    /// Send state label text
    private var sendStateLabel: some View {
        Group {
            switch sendState {
            case .queued:
                Text("Queued")
                    .foregroundStyle(theme.colors.textSecondary)
            case .sending:
                Text("Sending...")
                    .foregroundStyle(theme.colors.textSecondary)
            case .failed:
                Text("Failed to send")
                    .foregroundStyle(theme.colors.destructive)
            case .none, .sent:
                EmptyView()
            }
        }
        .font(theme.typography.caption)
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        switch sendState {
        case .failed:
            Button {
                onRetry()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(theme.typography.bodyLarge)
                    .foregroundStyle(theme.colors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry sending")
        case .queued:
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle")
                    .font(theme.typography.bodyLarge)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel sending")
        case .sending, .none, .sent:
            EmptyView()
        }
    }

    // MARK: - Recipient Parsing

    /// Parses the first recipient email from a JSON array string.
    /// Falls back to the raw string if JSON parsing fails.
    private func parseFirstRecipient(from jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8) else {
            return jsonString
        }
        do {
            let addresses = try JSONDecoder().decode([String].self, from: data)
            if let first = addresses.first, !first.isEmpty {
                return first
            }
            return jsonString
        } catch {
            return jsonString
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts: [String] = []

        parts.append("To \(recipientDisplay)")
        parts.append(email.subject)

        if let snippet = email.snippet, !snippet.isEmpty {
            parts.append(snippet)
        }

        if !timestampText.isEmpty {
            parts.append(timestampText)
        }

        switch sendState {
        case .queued:
            parts.append("Queued for sending")
        case .sending:
            parts.append("Sending in progress")
        case .failed:
            parts.append("Failed to send")
        case .none, .sent:
            break
        }

        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

#Preview("Queued Email") {
    let email = Email(
        accountId: "acc-1",
        threadId: "thread-1",
        messageId: "msg-1",
        fromAddress: "me@example.com",
        toAddresses: "[\"alice@example.com\",\"bob@example.com\"]",
        subject: "Quarterly Report Draft",
        snippet: "Please find attached the latest quarterly figures for review.",
        sendState: SendState.queued.rawValue,
        sendQueuedDate: Date()
    )
    return List {
        OutboxRowView(
            email: email,
            onRetry: { },
            onCancel: { }
        )
    }
    .listStyle(.plain)
    .environment(ThemeProvider())
}

#Preview("Sending Email") {
    let email = Email(
        accountId: "acc-1",
        threadId: "thread-2",
        messageId: "msg-2",
        fromAddress: "me@example.com",
        toAddresses: "[\"team@company.com\"]",
        subject: "Meeting Notes - Standup",
        snippet: "Here are the notes from today's standup meeting.",
        sendState: SendState.sending.rawValue,
        sendQueuedDate: Calendar.current.date(byAdding: .minute, value: -2, to: .now)
    )
    return List {
        OutboxRowView(
            email: email,
            onRetry: { },
            onCancel: { }
        )
    }
    .listStyle(.plain)
    .environment(ThemeProvider())
}

#Preview("Failed Email") {
    let email = Email(
        accountId: "acc-1",
        threadId: "thread-3",
        messageId: "msg-3",
        fromAddress: "me@example.com",
        toAddresses: "[\"client@external.com\"]",
        subject: "Invoice #2024-0042",
        snippet: "Please find attached your invoice for December services.",
        sendState: SendState.failed.rawValue,
        sendRetryCount: 3,
        sendQueuedDate: Calendar.current.date(byAdding: .hour, value: -1, to: .now)
    )
    return List {
        OutboxRowView(
            email: email,
            onRetry: { },
            onCancel: { }
        )
    }
    .listStyle(.plain)
    .environment(ThemeProvider())
}

#Preview("Multiple Outbox States") {
    let queued = Email(
        accountId: "acc-1",
        threadId: "thread-1",
        messageId: "msg-1",
        fromAddress: "me@example.com",
        toAddresses: "[\"alice@example.com\"]",
        subject: "Weekend Plans",
        snippet: "Are we still on for Saturday?",
        sendState: SendState.queued.rawValue,
        sendQueuedDate: Date()
    )
    let sending = Email(
        accountId: "acc-1",
        threadId: "thread-2",
        messageId: "msg-2",
        fromAddress: "me@example.com",
        toAddresses: "[\"bob@example.com\"]",
        subject: "Project Update",
        snippet: "The latest build is looking great.",
        sendState: SendState.sending.rawValue,
        sendQueuedDate: Calendar.current.date(byAdding: .minute, value: -1, to: .now)
    )
    let failed = Email(
        accountId: "acc-1",
        threadId: "thread-3",
        messageId: "msg-3",
        fromAddress: "me@example.com",
        toAddresses: "[\"support@vendor.com\"]",
        subject: "License Renewal",
        snippet: "We need to renew our enterprise license before end of month.",
        sendState: SendState.failed.rawValue,
        sendRetryCount: 2,
        sendQueuedDate: Calendar.current.date(byAdding: .hour, value: -3, to: .now)
    )
    return List {
        OutboxRowView(email: queued, onRetry: { }, onCancel: { })
        OutboxRowView(email: sending, onRetry: { }, onCancel: { })
        OutboxRowView(email: failed, onRetry: { }, onCancel: { })
    }
    .listStyle(.plain)
    .environment(ThemeProvider())
}
