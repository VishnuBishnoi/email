#if os(macOS)
import SwiftUI

/// macOS sidebar with Finder-style sections and icon + label rows.
///
/// Account switching is available from the bottom-left control.
///
/// Spec ref: FR-MAC-02 (Sidebar — Folder and Account Navigation)
struct SidebarView: View {
    @Environment(ThemeProvider.self) private var theme
    let accounts: [Account]
    let folders: [Folder]
    @Binding var selectedAccount: Account?
    @Binding var selectedFolder: Folder?
    let unreadCounts: [String?: Int]
    let outboxCount: Int

    let onSelectUnifiedInbox: () -> Void
    let onSelectAccount: (Account) -> Void
    let onSelectFolder: (Folder) -> Void
    let onAddAccount: () -> Void
    let onRemoveAccount: (Account) -> Void

    @State private var showRemoveConfirmation = false
    @State private var accountToRemove: Account?

    private enum ShortcutKind: String, CaseIterable, Identifiable {
        case inbox
        case starred
        case sent
        case drafts
        case spam
        case trash
        case outbox

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.sm) {
                    sectionHeader("Quick Access")
                    VStack(spacing: theme.spacing.xxs) {
                        sidebarRow(
                            title: "All Inboxes",
                            icon: "tray.2",
                            isSelected: selectedAccount == nil && selectedFolder == nil,
                            badgeCount: unreadCounts[nil]
                        ) {
                            onSelectUnifiedInbox()
                        }
                    }

                    sectionHeader("Mailboxes")
                    VStack(spacing: theme.spacing.xxs) {
                        ForEach(ShortcutKind.allCases) { kind in
                            sidebarRow(
                                title: title(for: kind),
                                icon: iconName(for: kind),
                                isSelected: isSelected(kind: kind),
                                badgeCount: badgeCount(for: kind)
                            ) {
                                handleSelection(for: kind)
                            }
                            .disabled(kind != .outbox && resolvedFolder(for: kind) == nil)
                        }
                    }
                }
                .padding(.horizontal, theme.spacing.md)
                .padding(.vertical, theme.spacing.md)
            }

            Divider()
            bottomBar
        }
        .alert("Remove Account", isPresented: $showRemoveConfirmation) {
            Button("Remove", role: .destructive) {
                if let account = accountToRemove {
                    onRemoveAccount(account)
                    accountToRemove = nil
                }
            }
            Button("Cancel", role: .cancel) {
                accountToRemove = nil
            }
        } message: {
            if let account = accountToRemove {
                Text("Remove \(account.email)? All local emails, drafts, and cached data for this account will be deleted.")
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(theme.typography.labelMedium)
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.top, theme.spacing.xs)
    }

    private func sidebarRow(
        title: String,
        icon: String,
        isSelected: Bool,
        badgeCount: Int?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 18, alignment: .center)

                Text(title)
                    .font(theme.typography.bodySmall)
                    .lineLimit(1)

                Spacer()

                if let badgeCount, badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(theme.typography.labelSmall)
                        .foregroundStyle(theme.colors.textInverse)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.colors.accent, in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? theme.colors.textPrimary : theme.colors.textPrimary)
            .padding(.horizontal, theme.spacing.sm)
            .padding(.vertical, theme.spacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? theme.colors.accentMuted : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var bottomBar: some View {
        HStack(spacing: theme.spacing.md) {
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 17))
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Open Settings")

            Menu {
                Button("All Inboxes") {
                    onSelectUnifiedInbox()
                }

                if !accounts.isEmpty {
                    Divider()
                    ForEach(accounts, id: \.id) { account in
                        Button {
                            onSelectAccount(account)
                        } label: {
                            if selectedAccount?.id == account.id {
                                Label(account.email, systemImage: "checkmark")
                            } else {
                                Text(account.email)
                            }
                        }
                    }
                }

                Divider()
                Button("Add Account") {
                    onAddAccount()
                }
                if let selectedAccount {
                    Button("Remove \(selectedAccount.email)", role: .destructive) {
                        accountToRemove = selectedAccount
                        showRemoveConfirmation = true
                    }
                }
            } label: {
                HStack(spacing: theme.spacing.xs) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 18))
                    Text(selectedAccount?.email ?? "Accounts")
                        .font(theme.typography.bodyMedium)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(theme.typography.caption)
                }
            }
            .menuStyle(.borderlessButton)
            .help("Switch Account")
            .accessibilityLabel("Switch Account")

            Spacer()
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm)
        .background(.bar)
    }

    private func title(for kind: ShortcutKind) -> String {
        switch kind {
        case .inbox: return "Inbox"
        case .starred: return "Starred"
        case .sent: return "Sent"
        case .drafts: return "Drafts"
        case .spam: return "Spam"
        case .trash: return "Trash"
        case .outbox: return "Outbox"
        }
    }

    private func iconName(for kind: ShortcutKind) -> String {
        switch kind {
        case .inbox: return "tray"
        case .starred: return "star"
        case .sent: return "paperplane"
        case .drafts: return "doc.text"
        case .spam: return "xmark.shield"
        case .trash: return "trash"
        case .outbox: return "tray.and.arrow.up"
        }
    }

    private func isSelected(kind: ShortcutKind) -> Bool {
        if kind == .outbox {
            guard let selectedFolder else { return false }
            return selectedFolder.name == "Outbox" && FolderType(rawValue: selectedFolder.folderType) == nil
        }

        guard let selectedFolder else { return false }
        return selectedFolder.folderType == folderType(for: kind)?.rawValue
    }

    private func badgeCount(for kind: ShortcutKind) -> Int? {
        if kind == .outbox {
            return outboxCount > 0 ? outboxCount : nil
        }
        guard let folder = resolvedFolder(for: kind) else { return nil }
        if folder.unreadCount > 0, kind == .inbox || kind == .spam || kind == .drafts {
            return folder.unreadCount
        }
        return nil
    }

    private func handleSelection(for kind: ShortcutKind) {
        if kind == .outbox {
            onSelectFolder(Folder(name: "Outbox", imapPath: "OUTBOX", folderType: ""))
            return
        }
        guard let folder = resolvedFolder(for: kind) else { return }
        onSelectFolder(folder)
    }

    private func folderType(for kind: ShortcutKind) -> FolderType? {
        switch kind {
        case .inbox: return .inbox
        case .starred: return .starred
        case .sent: return .sent
        case .drafts: return .drafts
        case .spam: return .spam
        case .trash: return .trash
        case .outbox: return nil
        }
    }

    private func resolvedFolder(for kind: ShortcutKind) -> Folder? {
        guard let type = folderType(for: kind) else { return nil }
        let filtered = folders.filter { $0.folderType == type.rawValue }
        if let selectedAccount {
            return filtered.first(where: { $0.account?.id == selectedAccount.id })
        }
        return filtered.first
    }
}
#endif
