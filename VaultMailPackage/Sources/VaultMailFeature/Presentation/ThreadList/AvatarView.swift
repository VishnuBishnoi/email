import SwiftUI

/// Avatar circle with initials and deterministic background color.
/// Stacks up to 2 avatars for multi-participant threads.
/// Optional account color dot for unified inbox mode.
///
/// Spec ref: Thread List spec FR-TL-01
struct AvatarView: View {
    let participants: [Participant]
    var accountColor: Color? = nil

    @Environment(ThemeProvider.self) private var theme

    // MARK: - Constants

    private static let accountDotSize: CGFloat = 8
    private static let stackOffset: CGFloat = 12

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarContent
            accountDot
        }
        .accessibilityHidden(true)
    }

    // MARK: - Avatar Content

    @ViewBuilder
    private var avatarContent: some View {
        if participants.count <= 1 {
            singleAvatar(for: participants.first)
        } else {
            stackedAvatars
        }
    }

    private func singleAvatar(for participant: Participant?) -> some View {
        let email = participant?.email ?? ""
        let brandInfo = BrandIconProvider.brand(for: email)
        let initials = brandInfo?.initial ?? Self.initials(for: participant)
        let color = brandInfo?.color ?? Self.color(for: email, palette: theme.colors.avatarPalette)

        return CachedFaviconView(
            email: email,
            diameter: theme.spacing.avatarSize,
            fallbackColor: color,
            initials: initials,
            initialsFontSize: nil
        )
    }

    private var stackedAvatars: some View {
        ZStack {
            // Second participant (background, offset right)
            if participants.count > 1 {
                smallAvatar(for: participants[1])
                    .offset(x: Self.stackOffset, y: Self.stackOffset)
            }
            // First participant (foreground)
            smallAvatar(for: participants[0])
                .offset(x: -Self.stackOffset / 2, y: -Self.stackOffset / 2)
        }
        .frame(width: theme.spacing.avatarSize, height: theme.spacing.avatarSize)
    }

    private func smallAvatar(for participant: Participant) -> some View {
        let brandInfo = BrandIconProvider.brand(for: participant.email)
        let initials = brandInfo?.initial ?? Self.initials(for: participant)
        let color = brandInfo?.color ?? Self.color(for: participant.email, palette: theme.colors.avatarPalette)

        return CachedFaviconView(
            email: participant.email,
            diameter: theme.spacing.avatarSizeSmall,
            fallbackColor: color,
            initials: initials,
            initialsFontSize: 11
        )
        .overlay {
            Circle()
                .stroke(theme.colors.background, lineWidth: 1.5)
        }
    }

    // MARK: - Account Dot

    @ViewBuilder
    private var accountDot: some View {
        if let accountColor {
            Circle()
                .fill(accountColor)
                .frame(width: Self.accountDotSize, height: Self.accountDotSize)
                .overlay {
                    Circle()
                        .stroke(theme.colors.background, lineWidth: 1)
                }
        }
    }

    // MARK: - Helpers

    /// Deterministic color derived from email address hash.
    static func color(for email: String, palette: [Color] = ThemeColorFactory.avatarPalette) -> Color {
        guard !email.isEmpty else { return palette[0] }
        // Use a stable hash instead of hashValue (which may vary across runs)
        let hash = email.utf8.reduce(0) { ($0 &+ Int($1)) &* 31 }
        let index = abs(hash) % palette.count
        return palette[index]
    }

    /// Extract initials from a participant.
    /// - Name present: first letter of first word + first letter of last word
    /// - Email only: first 2 characters of the email prefix
    static func initials(for participant: Participant?) -> String {
        guard let participant else { return "?" }

        if let name = participant.name, !name.isEmpty {
            let words = name.split(separator: " ")
            if words.count >= 2,
               let first = words.first?.first,
               let last = words.last?.first {
                return "\(first)\(last)".uppercased()
            } else if let first = words.first?.first {
                return String(first).uppercased()
            }
        }

        // Fallback to email prefix
        let prefix = participant.email.components(separatedBy: "@").first ?? participant.email
        let chars = prefix.prefix(2)
        return chars.uppercased()
    }
}

// MARK: - Previews

#Preview("Single Participant") {
    AvatarView(
        participants: [
            Participant(name: "John Smith", email: "john@example.com")
        ]
    )
    .environment(ThemeProvider())
    .padding()
}

#Preview("Two Participants") {
    AvatarView(
        participants: [
            Participant(name: "Alice Chen", email: "alice@example.com"),
            Participant(name: "Bob Jones", email: "bob@example.com")
        ]
    )
    .environment(ThemeProvider())
    .padding()
}

#Preview("Email Only") {
    AvatarView(
        participants: [
            Participant(name: nil, email: "support@company.io")
        ]
    )
    .environment(ThemeProvider())
    .padding()
}

#Preview("With Account Color") {
    AvatarView(
        participants: [
            Participant(name: "Jane Doe", email: "jane@work.com")
        ],
        accountColor: .blue
    )
    .environment(ThemeProvider())
    .padding()
}

#Preview("No Participants") {
    AvatarView(participants: [])
        .environment(ThemeProvider())
        .padding()
}
