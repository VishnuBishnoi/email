import SwiftUI

/// Header view for a single email message in the detail screen.
/// Shows sender avatar, sender info, timestamp, and expandable recipient details.
///
/// - Collapsed: avatar, sender name, relative date (single line)
/// - Expanded: avatar, sender name + email, timestamp, To/CC recipients
struct MessageHeaderView: View {
    let email: Email
    let isExpanded: Bool
    let onStarToggle: () -> Void

    // MARK: - State

    @State private var showAllRecipients = false

    // MARK: - Constants

    private static let avatarDiameter: CGFloat = 40
    private static let visibleRecipientLimit = 2

    // MARK: - Derived Properties

    private var senderParticipant: Participant {
        Participant(name: email.fromName, email: email.fromAddress)
    }

    private var senderInitial: String {
        let displayName = senderParticipant.displayName
        guard let first = displayName.first else { return "?" }
        return String(first).uppercased()
    }

    private var avatarColor: Color {
        AvatarView.color(for: email.fromAddress)
    }

    private var timestampText: String {
        email.dateReceived?.relativeThreadFormat() ?? ""
    }

    private var toRecipients: [Participant] {
        Participant.decode(from: email.toAddresses)
    }

    private var ccRecipients: [Participant] {
        Participant.decode(from: email.ccAddresses)
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            senderAvatar

            if isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Avatar

    private var senderAvatar: some View {
        Circle()
            .fill(avatarColor)
            .frame(width: Self.avatarDiameter, height: Self.avatarDiameter)
            .overlay {
                Text(senderInitial)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Avatar for \(senderParticipant.displayName)")
    }

    // MARK: - Collapsed Layout

    private var collapsedContent: some View {
        HStack {
            Text(senderParticipant.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Spacer()

            Text(timestampText)
                .font(.caption)
                .foregroundStyle(.secondary)

            starButton
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(collapsedAccessibilityLabel)
    }

    // MARK: - Expanded Layout

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Row 1: sender name + star
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(senderParticipant.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Text(email.fromAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(timestampText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    starButton
                }
            }

            // Recipients
            recipientsSection
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Recipients Section

    @ViewBuilder
    private var recipientsSection: some View {
        if !toRecipients.isEmpty {
            recipientRow(label: "To", participants: toRecipients)
        }

        if !ccRecipients.isEmpty {
            recipientRow(label: "CC", participants: ccRecipients)
        }
    }

    private func recipientRow(label: String, participants: [Participant]) -> some View {
        let visibleParticipants: [Participant]
        let hiddenCount: Int

        if showAllRecipients || participants.count <= Self.visibleRecipientLimit {
            visibleParticipants = participants
            hiddenCount = 0
        } else {
            visibleParticipants = Array(participants.prefix(Self.visibleRecipientLimit))
            hiddenCount = participants.count - Self.visibleRecipientLimit
        }

        let namesText = visibleParticipants
            .map(\.displayName)
            .joined(separator: ", ")

        return HStack(spacing: 4) {
            Text("\(label):")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(namesText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if hiddenCount > 0 {
                Button {
                    showAllRecipients = true
                } label: {
                    Text("and \(hiddenCount) more")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(hiddenCount) more \(label) recipients")
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(participants.map(\.displayName).joined(separator: ", "))")
    }

    // MARK: - Star Button

    private var starButton: some View {
        Button(action: onStarToggle) {
            Image(systemName: email.isStarred ? "star.fill" : "star")
                .font(.subheadline)
                .foregroundStyle(email.isStarred ? .yellow : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(email.isStarred ? "Remove star" : "Add star")
    }

    // MARK: - Accessibility

    private var collapsedAccessibilityLabel: String {
        var parts: [String] = []
        parts.append("From \(senderParticipant.displayName)")
        if !timestampText.isEmpty {
            parts.append(timestampText)
        }
        parts.append(email.isRead ? "Read" : "Unread")
        if email.isStarred {
            parts.append("Starred")
        }
        return parts.joined(separator: ", ")
    }
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
        dateReceived: Date(),
        isRead: true,
        isStarred: false
    )

    return MessageHeaderView(
        email: email,
        isExpanded: false,
        onStarToggle: {}
    )
    .padding()
}

#Preview("Expanded - Few Recipients") {
    let email = Email(
        accountId: "acc-1",
        threadId: "thread-1",
        messageId: "msg-2",
        fromAddress: "carol@company.com",
        fromName: "Carol White",
        toAddresses: Participant.encode([
            Participant(name: "Alice Johnson", email: "alice@example.com"),
            Participant(name: "Bob Smith", email: "bob@example.com")
        ]),
        ccAddresses: Participant.encode([
            Participant(name: "Dave Lee", email: "dave@example.com")
        ]),
        subject: "Meeting Follow-up",
        dateReceived: Calendar.current.date(byAdding: .hour, value: -2, to: .now),
        isRead: false,
        isStarred: true
    )

    return MessageHeaderView(
        email: email,
        isExpanded: true,
        onStarToggle: {}
    )
    .padding()
}

#Preview("Expanded - Many Recipients") {
    let email = Email(
        accountId: "acc-1",
        threadId: "thread-1",
        messageId: "msg-3",
        fromAddress: "team-lead@company.com",
        fromName: "Team Lead",
        toAddresses: Participant.encode([
            Participant(name: "Alice Johnson", email: "alice@example.com"),
            Participant(name: "Bob Smith", email: "bob@example.com"),
            Participant(name: "Carol White", email: "carol@example.com"),
            Participant(name: "Dave Lee", email: "dave@example.com"),
            Participant(name: "Eve Park", email: "eve@example.com")
        ]),
        ccAddresses: Participant.encode([
            Participant(name: "Frank Miller", email: "frank@example.com"),
            Participant(name: "Grace Kim", email: "grace@example.com"),
            Participant(name: "Henry Chen", email: "henry@example.com")
        ]),
        subject: "All Hands Meeting",
        dateReceived: Calendar.current.date(byAdding: .day, value: -1, to: .now),
        isStarred: false
    )

    return MessageHeaderView(
        email: email,
        isExpanded: true,
        onStarToggle: {}
    )
    .padding()
}

#Preview("Starred - Email Only Sender") {
    let email = Email(
        accountId: "acc-1",
        threadId: "thread-1",
        messageId: "msg-4",
        fromAddress: "noreply@service.io",
        toAddresses: Participant.encode([
            Participant(name: nil, email: "user@example.com")
        ]),
        subject: "Your receipt",
        dateReceived: Calendar.current.date(byAdding: .month, value: -1, to: .now),
        isStarred: true
    )

    return MessageHeaderView(
        email: email,
        isExpanded: false,
        onStarToggle: {}
    )
    .padding()
}
