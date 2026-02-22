#if os(macOS)
import SwiftUI

/// macOS sidebar with account selector, folder tree, and Unified Inbox.
///
/// Uses `.listStyle(.sidebar)` for native macOS appearance.
/// Each account is expandable with system folders in fixed order,
/// followed by custom labels, plus a virtual Outbox entry.
///
/// Bottom bar provides quick access to Settings and Add Account.
/// Right-click on account headers provides Remove Account option.
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

    /// Tracks which accounts are expanded in the sidebar.
    @SceneStorage("macOS.sidebarExpandedAccounts")
    private var expandedAccountsData: String = ""

    @State private var expandedAccounts: Set<String> = []
    @State private var folderLoadError: Set<String> = []
    @State private var isAddingAccount = false
    @State private var showRemoveConfirmation = false
    @State private var accountToRemove: Account?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding<String?>(
                get: { selectedFolder?.id },
                set: { newId in
                    // Find and select the folder with this ID
                    if let folderId = newId,
                       let folder = allFolders.first(where: { $0.id == folderId }) {
                        onSelectFolder(folder)
                    }
                }
            )) {
                // Unified Inbox
                unifiedInboxRow

                // Per-account sections
                ForEach(accounts, id: \.id) { account in
                    accountSection(for: account)
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Bottom bar with settings and add account
            sidebarBottomBar
        }
        .onAppear {
            // Restore expanded accounts from SceneStorage
            expandedAccounts = Set(expandedAccountsData.split(separator: ",").map(String.init))
            // Auto-expand first account if none expanded
            if expandedAccounts.isEmpty, let first = accounts.first {
                expandedAccounts.insert(first.id)
            }
        }
        .onChange(of: expandedAccounts) {
            expandedAccountsData = expandedAccounts.joined(separator: ",")
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

    // MARK: - Bottom Bar

    private var sidebarBottomBar: some View {
        HStack(spacing: theme.spacing.md) {
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Open Settings")

            Button {
                onAddAccount()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .disabled(isAddingAccount)
            .help("Add Account")
            .accessibilityLabel("Add Account")

            Spacer()
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm)
        .background(.bar)
    }

    // MARK: - All Folders Helper

    private var allFolders: [Folder] {
        folders
    }

    // MARK: - Unified Inbox

    private var unifiedInboxRow: some View {
        Button {
            onSelectUnifiedInbox()
        } label: {
            Label("All Inboxes", systemImage: "tray.2")
        }
        .font(selectedAccount == nil && selectedFolder == nil ? theme.typography.titleMedium : theme.typography.bodyLarge)
        .tag("__unified__" as String?)
        .accessibilityLabel("All Inboxes, unified view")
    }

    // MARK: - Account Section

    @ViewBuilder
    private func accountSection(for account: Account) -> some View {
        let isExpanded = Binding<Bool>(
            get: { expandedAccounts.contains(account.id) },
            set: { newValue in
                if newValue { expandedAccounts.insert(account.id) }
                else { expandedAccounts.remove(account.id) }
            }
        )

        DisclosureGroup(isExpanded: isExpanded) {
            // System folders
            let accountFolders = folders.filter { $0.account?.id == account.id }
            let systemFolders = sortedSystemFolders(from: accountFolders)
            let customFolders = sortedCustomFolders(from: accountFolders)

            ForEach(systemFolders, id: \.id) { folder in
                folderRow(folder: folder)
            }

            // Virtual Outbox
            outboxRow(for: account)

            // Custom Labels
            if !customFolders.isEmpty {
                Section("Labels") {
                    ForEach(customFolders, id: \.id) { folder in
                        folderRow(folder: folder)
                    }
                }
            }
        } label: {
            HStack {
                Image(systemName: "person.circle")
                    .foregroundStyle(selectedAccount?.id == account.id ? theme.colors.accent : theme.colors.textSecondary)
                Text(account.email)
                    .font(selectedAccount?.id == account.id ? theme.typography.titleMedium : theme.typography.bodyLarge)
                    .lineLimit(1)
            }
            .contextMenu {
                Button(role: .destructive) {
                    accountToRemove = account
                    showRemoveConfirmation = true
                } label: {
                    Label("Remove Account", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Folder Row

    private func folderRow(folder: Folder) -> some View {
        Label {
            HStack {
                Text(folder.name)
                    .lineLimit(1)
                Spacer()
                if let count = badgeCount(for: folder), count > 0 {
                    Text("\(count)")
                        .font(theme.typography.labelSmall)
                        .foregroundStyle(theme.colors.textInverse)
                        .padding(.horizontal, theme.spacing.chipVertical)
                        .padding(.vertical, 1)
                        .background(theme.colors.accent, in: Capsule())
                }
            }
        } icon: {
            Image(systemName: iconName(for: folder.folderType))
        }
        .tag(folder.id as String?)
        .accessibilityLabel("\(folder.name)\(badgeLabel(for: folder))")
    }

    // MARK: - Virtual Outbox Row

    private func outboxRow(for account: Account) -> some View {
        Label {
            HStack {
                Text("Outbox")
                Spacer()
                if outboxCount > 0 {
                    Text("\(outboxCount)")
                        .font(theme.typography.labelSmall)
                        .foregroundStyle(theme.colors.textInverse)
                        .padding(.horizontal, theme.spacing.chipVertical)
                        .padding(.vertical, 1)
                        .background(theme.colors.warning, in: Capsule())
                }
            }
        } icon: {
            Image(systemName: "tray.and.arrow.up")
        }
        .accessibilityLabel("Outbox\(outboxCount > 0 ? ", \(outboxCount) pending" : "")")
    }

    // MARK: - Sorting

    private static let systemFolderOrder: [FolderType] = [
        .inbox, .starred, .sent, .drafts, .spam, .trash, .archive
    ]

    private func sortedSystemFolders(from accountFolders: [Folder]) -> [Folder] {
        let systemTypes = Set(Self.systemFolderOrder.map(\.rawValue))
        return accountFolders
            .filter { systemTypes.contains($0.folderType) }
            .sorted { lhs, rhs in
                let li = Self.systemFolderOrder.firstIndex(where: { $0.rawValue == lhs.folderType }) ?? Int.max
                let ri = Self.systemFolderOrder.firstIndex(where: { $0.rawValue == rhs.folderType }) ?? Int.max
                return li < ri
            }
    }

    private func sortedCustomFolders(from accountFolders: [Folder]) -> [Folder] {
        accountFolders
            .filter { $0.folderType == FolderType.custom.rawValue }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Badges

    private func badgeCount(for folder: Folder) -> Int? {
        switch FolderType(rawValue: folder.folderType) {
        case .inbox, .spam:
            return folder.unreadCount > 0 ? folder.unreadCount : nil
        case .drafts:
            return folder.unreadCount > 0 ? folder.unreadCount : nil
        default:
            return nil
        }
    }

    private func badgeLabel(for folder: Folder) -> String {
        if let count = badgeCount(for: folder), count > 0 {
            return ", \(count) unread"
        }
        return ""
    }

    // MARK: - Icons

    private func iconName(for folderType: String) -> String {
        switch FolderType(rawValue: folderType) {
        case .inbox: return "tray"
        case .starred: return "star"
        case .sent: return "paperplane"
        case .drafts: return "doc.text"
        case .trash: return "trash"
        case .spam: return "xmark.shield"
        case .archive: return "archivebox"
        case .custom: return "folder"
        case .none: return "folder"
        }
    }
}
#endif
