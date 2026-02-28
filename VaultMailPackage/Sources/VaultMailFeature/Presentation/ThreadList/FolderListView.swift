import SwiftUI

/// Folder navigation view showing system folders and custom labels.
///
/// Presents system mailboxes (inbox, starred, sent, drafts, spam, trash, archive)
/// plus a virtual Outbox row, followed by custom labels. Dismisses on selection.
///
/// Spec ref: Thread List spec FR-TL-06 (Folder navigation)
struct FolderListView: View {
    let folders: [Folder]
    let outboxCount: Int
    let onSelectFolder: (Folder) -> Void
    let onSelectOutbox: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme

    // MARK: - Folder Classification

    /// Defines the sort order for system folder types.
    private static let systemFolderOrder: [FolderType] = [
        .inbox, .starred, .sent, .drafts, .spam, .trash, .archive
    ]

    /// System folders filtered and sorted by the canonical order.
    private var systemFolders: [Folder] {
        let systemTypes = Set(Self.systemFolderOrder.map(\.rawValue))
        let filtered = folders.filter { systemTypes.contains($0.folderType) }
        return filtered.sorted { lhs, rhs in
            let lhsIndex = Self.systemFolderOrder.firstIndex(where: { $0.rawValue == lhs.folderType }) ?? Int.max
            let rhsIndex = Self.systemFolderOrder.firstIndex(where: { $0.rawValue == rhs.folderType }) ?? Int.max
            return lhsIndex < rhsIndex
        }
    }

    /// Custom label folders sorted alphabetically by name.
    private var customFolders: [Folder] {
        folders
            .filter { $0.folderType == FolderType.custom.rawValue }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Icon Mapping

    /// Returns the SF Symbol name for a given folder type raw value.
    private func iconName(for folderType: String) -> String {
        switch FolderType(rawValue: folderType) {
        case .inbox: "tray"
        case .starred: "star"
        case .sent: "paperplane"
        case .drafts: "doc.text"
        case .spam: "exclamationmark.triangle"
        case .trash: "trash"
        case .archive: "archivebox"
        case .custom, .none: "tag"
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                mailboxesSection
                if !customFolders.isEmpty {
                    labelsSection
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Folders")
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

    // MARK: - Mailboxes Section

    private var mailboxesSection: some View {
        Section("Mailboxes") {
            ForEach(systemFolders, id: \.id) { folder in
                folderRow(folder: folder)
            }
            outboxRow
        }
    }

    // MARK: - Labels Section

    private var labelsSection: some View {
        Section("Labels") {
            ForEach(customFolders, id: \.id) { folder in
                folderRow(folder: folder, isCustom: true)
            }
        }
    }

    // MARK: - Folder Row

    private func folderRow(folder: Folder, isCustom: Bool = false) -> some View {
        Button {
            onSelectFolder(folder)
            dismiss()
        } label: {
            HStack {
                Label(folder.name, systemImage: isCustom ? "tag" : iconName(for: folder.folderType))
                    .foregroundStyle(theme.colors.textPrimary)

                Spacer()

                if folder.unreadCount > 0 {
                    unreadBadge(count: folder.unreadCount)
                }
            }
        }
        .accessibilityLabel(folderAccessibilityLabel(name: folder.name, unreadCount: folder.unreadCount))
    }

    // MARK: - Outbox Row

    private var outboxRow: some View {
        Button {
            onSelectOutbox()
            dismiss()
        } label: {
            HStack {
                Label("Outbox", systemImage: "tray.and.arrow.up")
                    .foregroundStyle(theme.colors.textPrimary)

                Spacer()

                if outboxCount > 0 {
                    unreadBadge(count: outboxCount)
                }
            }
        }
        .accessibilityLabel(folderAccessibilityLabel(name: "Outbox", unreadCount: outboxCount))
    }

    // MARK: - Badge

    private func unreadBadge(count: Int) -> some View {
        Text("\(count)")
            .font(theme.typography.labelSmall)
            .padding(.horizontal, theme.spacing.chipHorizontal / 2)
            .padding(.vertical, theme.spacing.xxs)
            .background(theme.colors.accentMuted, in: Capsule())
    }

    // MARK: - Accessibility

    private func folderAccessibilityLabel(name: String, unreadCount: Int) -> String {
        if unreadCount > 0 {
            return "\(name), \(unreadCount) unread"
        }
        return name
    }
}

// MARK: - Previews

#Preview("Folders with Badges") {
    let folders: [Folder] = [
        Folder(name: "Inbox", imapPath: "INBOX", unreadCount: 12, totalCount: 340, folderType: FolderType.inbox.rawValue),
        Folder(name: "Starred", imapPath: "[Gmail]/Starred", unreadCount: 0, totalCount: 28, folderType: FolderType.starred.rawValue),
        Folder(name: "Sent Mail", imapPath: "[Gmail]/Sent Mail", unreadCount: 0, totalCount: 150, folderType: FolderType.sent.rawValue),
        Folder(name: "Drafts", imapPath: "[Gmail]/Drafts", unreadCount: 2, totalCount: 5, folderType: FolderType.drafts.rawValue),
        Folder(name: "Spam", imapPath: "[Gmail]/Spam", unreadCount: 7, totalCount: 42, folderType: FolderType.spam.rawValue),
        Folder(name: "Trash", imapPath: "[Gmail]/Trash", unreadCount: 0, totalCount: 18, folderType: FolderType.trash.rawValue),
        Folder(name: "Archive", imapPath: "[Gmail]/All Mail", unreadCount: 0, totalCount: 1200, folderType: FolderType.archive.rawValue),
        Folder(name: "Work Projects", imapPath: "Work Projects", unreadCount: 3, totalCount: 45, folderType: FolderType.custom.rawValue),
        Folder(name: "Newsletters", imapPath: "Newsletters", unreadCount: 0, totalCount: 89, folderType: FolderType.custom.rawValue),
        Folder(name: "Receipts", imapPath: "Receipts", unreadCount: 1, totalCount: 33, folderType: FolderType.custom.rawValue),
    ]
    return FolderListView(
        folders: folders,
        outboxCount: 2,
        onSelectFolder: { _ in },
        onSelectOutbox: { }
    )
}

#Preview("No Custom Labels") {
    let folders: [Folder] = [
        Folder(name: "Inbox", imapPath: "INBOX", unreadCount: 5, totalCount: 100, folderType: FolderType.inbox.rawValue),
        Folder(name: "Sent", imapPath: "[Gmail]/Sent Mail", unreadCount: 0, totalCount: 50, folderType: FolderType.sent.rawValue),
        Folder(name: "Trash", imapPath: "[Gmail]/Trash", unreadCount: 0, totalCount: 10, folderType: FolderType.trash.rawValue),
    ]
    return FolderListView(
        folders: folders,
        outboxCount: 0,
        onSelectFolder: { _ in },
        onSelectOutbox: { }
    )
}

#Preview("Empty State") {
    FolderListView(
        folders: [],
        outboxCount: 0,
        onSelectFolder: { _ in },
        onSelectOutbox: { }
    )
}
