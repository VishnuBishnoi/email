import SwiftUI
import SwiftData

/// Sheet for switching between individual accounts or a unified "All Accounts" inbox.
///
/// Displays each configured account with its avatar, display name, email address,
/// inbox unread count, and a checkmark indicating the currently selected account.
/// The first row always offers "All Accounts" (unified inbox).
///
/// Spec ref: Thread List spec FR-TL account switching
struct AccountSwitcherSheet: View {
    let accounts: [Account]
    /// Currently selected account ID, or `nil` for unified/all accounts.
    let selectedAccountId: String?
    /// Called when the user picks an account. `nil` means unified inbox.
    let onSelectAccount: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                allAccountsRow
                accountsSection
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Accounts")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - All Accounts Row

    private var allAccountsRow: some View {
        Section {
            Button {
                onSelectAccount(nil)
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "tray.2")
                        .font(theme.typography.titleSmall)
                        .foregroundStyle(theme.colors.textPrimary)
                        .frame(width: theme.spacing.avatarSizeSmall, height: theme.spacing.avatarSizeSmall)

                    Text("All Accounts")
                        .foregroundStyle(theme.colors.textPrimary)

                    Spacer()

                    if totalUnreadCount > 0 {
                        unreadBadge(count: totalUnreadCount)
                    }

                    if selectedAccountId == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(theme.colors.accent)
                            .fontWeight(.semibold)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(allAccountsAccessibilityLabel)
        }
    }

    // MARK: - Per-Account Rows

    private var accountsSection: some View {
        Section {
            ForEach(accounts, id: \.id) { account in
                Button {
                    onSelectAccount(account.id)
                    dismiss()
                } label: {
                    accountRow(account)
                }
            }
        }
    }

    private func accountRow(_ account: Account) -> some View {
        let isSelected = selectedAccountId == account.id
        let unread = inboxUnreadCount(for: account)
        let initials = AvatarView.initials(
            for: Participant(name: account.displayName, email: account.email)
        )
        let color = AvatarView.color(for: account.email)

        return HStack(spacing: theme.spacing.md) {
            // Leading avatar circle
            Circle()
                .fill(color)
                .frame(width: 36, height: 36)
                .overlay {
                    Text(initials)
                        .font(theme.typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.colors.textInverse)
                }
                .accessibilityHidden(true)

            // Name + email
            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text(account.displayName)
                    .foregroundStyle(theme.colors.textPrimary)
                    .font(theme.typography.bodyLarge)
                    .lineLimit(1)

                Text(account.email)
                    .foregroundStyle(theme.colors.textSecondary)
                    .font(theme.typography.caption)
                    .lineLimit(1)
            }

            Spacer()

            // Trailing: unread badge + checkmark
            if unread > 0 {
                unreadBadge(count: unread)
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(theme.colors.accent)
                    .fontWeight(.semibold)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accountAccessibilityLabel(account, isSelected: isSelected, unread: unread))
    }

    // MARK: - Unread Badge

    private func unreadBadge(count: Int) -> some View {
        Text("\(count)")
            .font(theme.typography.labelSmall)
            .fontWeight(.semibold)
            .foregroundStyle(theme.colors.textInverse)
            .padding(.horizontal, theme.spacing.chipVertical)
            .padding(.vertical, theme.spacing.xxs)
            .background(theme.colors.accent, in: theme.shapes.capsuleShape)
            .accessibilityHidden(true)
    }

    // MARK: - Unread Helpers

    /// Total unread count across all accounts' inbox folders.
    private var totalUnreadCount: Int {
        accounts.reduce(0) { $0 + inboxUnreadCount(for: $1) }
    }

    /// Unread count for a single account's inbox folder(s).
    private func inboxUnreadCount(for account: Account) -> Int {
        account.folders
            .filter { $0.folderType == FolderType.inbox.rawValue }
            .reduce(0) { $0 + $1.unreadCount }
    }

    // MARK: - Accessibility

    private var allAccountsAccessibilityLabel: Text {
        var parts = "All Accounts"
        if totalUnreadCount > 0 {
            parts += ", \(totalUnreadCount) unread"
        }
        if selectedAccountId == nil {
            parts += ", selected"
        }
        return Text(parts)
    }

    private func accountAccessibilityLabel(
        _ account: Account,
        isSelected: Bool,
        unread: Int
    ) -> Text {
        var parts = "\(account.displayName), \(account.email)"
        if unread > 0 {
            parts += ", \(unread) unread"
        }
        if isSelected {
            parts += ", selected"
        }
        return Text(parts)
    }
}

// MARK: - Previews

#Preview("Multiple Accounts - Unified Selected") {
    AccountSwitcherSheet(
        accounts: previewAccounts(),
        selectedAccountId: nil,
        onSelectAccount: { _ in }
    )
    .environment(ThemeProvider())
}

#Preview("Multiple Accounts - One Selected") {
    AccountSwitcherSheet(
        accounts: previewAccounts(),
        selectedAccountId: "account-1",
        onSelectAccount: { _ in }
    )
    .environment(ThemeProvider())
}

#Preview("Single Account") {
    AccountSwitcherSheet(
        accounts: [previewAccounts()[0]],
        selectedAccountId: "account-1",
        onSelectAccount: { _ in }
    )
    .environment(ThemeProvider())
}

// MARK: - Preview Helpers

private func previewAccounts() -> [Account] {
    let account1 = Account(
        id: "account-1",
        email: "alice@proton.me",
        displayName: "Alice Johnson"
    )
    let inbox1 = Folder(
        name: "Inbox",
        imapPath: "INBOX",
        unreadCount: 12,
        totalCount: 150,
        folderType: FolderType.inbox.rawValue
    )
    inbox1.account = account1
    account1.folders = [inbox1]

    let account2 = Account(
        id: "account-2",
        email: "bob.smith@gmail.com",
        displayName: "Bob Smith"
    )
    let inbox2 = Folder(
        name: "Inbox",
        imapPath: "INBOX",
        unreadCount: 3,
        totalCount: 42,
        folderType: FolderType.inbox.rawValue
    )
    inbox2.account = account2
    account2.folders = [inbox2]

    let account3 = Account(
        id: "account-3",
        email: "carol@work.org",
        displayName: "Carol Davis"
    )
    let inbox3 = Folder(
        name: "Inbox",
        imapPath: "INBOX",
        unreadCount: 0,
        totalCount: 8,
        folderType: FolderType.inbox.rawValue
    )
    inbox3.account = account3
    account3.folders = [inbox3]

    return [account1, account2, account3]
}
