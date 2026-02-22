import SwiftUI

/// Sheet presenting a folder picker for the "Move to" action.
///
/// Folders are split into two sections:
/// - **System Folders** — all built-in folder types (inbox, sent, drafts, etc.)
/// - **Labels** — user-created custom folders
///
/// Tapping a row calls `onSelect` with the folder's ID and dismisses the sheet.
///
/// Spec ref: Thread List spec FR-TL-03
struct MoveToFolderSheet: View {
    let folders: [Folder]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeProvider.self) private var theme

    private var systemFolders: [Folder] {
        folders.filter { $0.folderType != FolderType.custom.rawValue }
    }

    private var customFolders: [Folder] {
        folders.filter { $0.folderType == FolderType.custom.rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                if !systemFolders.isEmpty {
                    Section("System Folders") {
                        ForEach(systemFolders, id: \.id) { folder in
                            folderRow(folder)
                        }
                    }
                }

                if !customFolders.isEmpty {
                    Section("Labels") {
                        ForEach(customFolders, id: \.id) { folder in
                            folderRow(folder)
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Move to Folder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Folder Row

    private func folderRow(_ folder: Folder) -> some View {
        Button {
            onSelect(folder.id)
            dismiss()
        } label: {
            HStack(spacing: theme.spacing.listRowSpacing) {
                Image(systemName: iconName(for: folder.folderType))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 24)

                Text(folder.name)
                    .foregroundStyle(theme.colors.textPrimary)
            }
        }
        .accessibilityLabel("Move to \(folder.name)")
    }

    // MARK: - Icon Mapping

    private func iconName(for folderType: String) -> String {
        guard let type = FolderType(rawValue: folderType) else {
            return "tag"
        }
        switch type {
        case .inbox:
            return "tray"
        case .sent:
            return "paperplane"
        case .drafts:
            return "doc"
        case .trash:
            return "trash"
        case .spam:
            return "exclamationmark.triangle"
        case .archive:
            return "archivebox"
        case .starred:
            return "star"
        case .custom:
            return "tag"
        }
    }
}

// MARK: - Previews

#Preview("Move to Folder") {
    let folders: [Folder] = [
        Folder(name: "Inbox", imapPath: "INBOX", folderType: FolderType.inbox.rawValue),
        Folder(name: "Sent Mail", imapPath: "[Gmail]/Sent Mail", folderType: FolderType.sent.rawValue),
        Folder(name: "Drafts", imapPath: "[Gmail]/Drafts", folderType: FolderType.drafts.rawValue),
        Folder(name: "Trash", imapPath: "[Gmail]/Trash", folderType: FolderType.trash.rawValue),
        Folder(name: "Spam", imapPath: "[Gmail]/Spam", folderType: FolderType.spam.rawValue),
        Folder(name: "Archive", imapPath: "[Gmail]/All Mail", folderType: FolderType.archive.rawValue),
        Folder(name: "Starred", imapPath: "[Gmail]/Starred", folderType: FolderType.starred.rawValue),
        Folder(name: "Work", imapPath: "Work", folderType: FolderType.custom.rawValue),
        Folder(name: "Personal", imapPath: "Personal", folderType: FolderType.custom.rawValue),
        Folder(name: "Receipts", imapPath: "Receipts", folderType: FolderType.custom.rawValue),
    ]
    MoveToFolderSheet(folders: folders, onSelect: { _ in })
        .environment(ThemeProvider())
}

#Preview("System Folders Only") {
    let folders: [Folder] = [
        Folder(name: "Inbox", imapPath: "INBOX", folderType: FolderType.inbox.rawValue),
        Folder(name: "Sent Mail", imapPath: "[Gmail]/Sent Mail", folderType: FolderType.sent.rawValue),
        Folder(name: "Archive", imapPath: "[Gmail]/All Mail", folderType: FolderType.archive.rawValue),
    ]
    MoveToFolderSheet(folders: folders, onSelect: { _ in })
        .environment(ThemeProvider())
}

#Preview("Custom Labels Only") {
    let folders: [Folder] = [
        Folder(name: "Work Projects", imapPath: "Work Projects", folderType: FolderType.custom.rawValue),
        Folder(name: "Travel", imapPath: "Travel", folderType: FolderType.custom.rawValue),
    ]
    MoveToFolderSheet(folders: folders, onSelect: { _ in })
        .environment(ThemeProvider())
}
