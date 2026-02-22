import SwiftUI

/// Bottom navigation bar for the thread list.
///
/// Displays 5 action buttons (Folders, Account, Search, Compose, Settings)
/// in a horizontal row at the bottom of the screen. Uses iOS 26 Liquid Glass
/// effects when available, falling back to `.ultraThinMaterial` on older iOS.
///
/// Follows the same component pattern as ``MultiSelectToolbar``.
///
/// Spec ref: Thread List toolbar migration
struct BottomTabBar: View {

    // MARK: - Properties

    @Environment(ThemeProvider.self) private var theme

    let folders: [Folder]
    let onSelectFolder: (Folder) -> Void
    let onAccountTap: () -> Void
    let onSearchTap: () -> Void
    let onComposeTap: () -> Void
    let onSettingsTap: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(theme.colors.separator)

            HStack {
                foldersMenu
                Spacer()
                tabButton(icon: "person.circle", label: "Account", action: onAccountTap)
                Spacer()
                tabButton(icon: "magnifyingglass", label: "Search", action: onSearchTap)
                Spacer()
                tabButton(icon: "square.and.pencil", label: "Compose", action: onComposeTap)
                Spacer()
                tabButton(icon: "gear", label: "Settings", action: onSettingsTap)
            }
            .padding(.horizontal, theme.spacing.xl)
            .padding(.top, theme.spacing.sm)
            .padding(.bottom, theme.spacing.xs)
        }
        .background(barBackground)
    }

    // MARK: - Folders Menu

    private var foldersMenu: some View {
        Menu {
            if folders.isEmpty {
                Text("No folders")
            } else {
                ForEach(folders, id: \.id) { folder in
                    Button {
                        onSelectFolder(folder)
                    } label: {
                        Label(folder.name, systemImage: folderIcon(for: folder))
                    }
                }
            }
        } label: {
            VStack(spacing: theme.spacing.xs) {
                Image(systemName: "folder")
                    .font(.system(size: theme.spacing.iconSize))
                Text("Folders")
                    .font(theme.typography.labelSmall)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(theme.colors.textPrimary)
        }
        .accessibilityLabel("Folders")
    }

    // MARK: - Tab Button

    private func tabButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: theme.spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: theme.spacing.iconSize))
                Text(label)
                    .font(theme.typography.labelSmall)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(label)
    }

    // MARK: - Background

    @ViewBuilder
    private var barBackground: some View {
        // iOS/macOS 26+: Liquid Glass effect; fallback: material blur
        if #available(iOS 26.0, macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular, in: .rect(cornerRadius: 0))
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - Folder Icon Helper

    private func folderIcon(for folder: Folder) -> String {
        guard let type = FolderType(rawValue: folder.folderType) else {
            return "folder"
        }
        switch type {
        case .inbox: return "tray"
        case .sent: return "paperplane"
        case .drafts: return "doc.text"
        case .trash: return "trash"
        case .spam: return "xmark.shield"
        case .archive: return "archivebox"
        case .starred: return "star"
        case .custom: return "folder"
        }
    }
}

// MARK: - Previews

#Preview("Default") {
    VStack {
        Spacer()
        BottomTabBar(
            folders: [],
            onSelectFolder: { _ in },
            onAccountTap: {},
            onSearchTap: {},
            onComposeTap: {},
            onSettingsTap: {}
        )
    }
    .environment(ThemeProvider())
}
