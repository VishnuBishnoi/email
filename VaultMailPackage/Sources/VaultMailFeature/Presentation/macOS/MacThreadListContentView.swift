#if os(macOS)
import SwiftUI

/// Thread list content for the macOS content column of NavigationSplitView.
///
/// Displays threads with single-click selection (not push navigation),
/// category segmented control, context menus, and pagination.
/// Reuses shared ThreadRowView for row content.
///
/// Spec ref: FR-MAC-04 (Thread List), FR-MAC-05 (Thread Interactions)
struct MacThreadListContentView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ThemeProvider.self) private var theme

    let viewState: MacOSMainView.ViewState
    let threads: [VaultMailFeature.Thread]
    @Binding var selectedThreadID: String?
    @Binding var selectedThreadIDs: Set<String>
    @Binding var selectedCategory: String?
    let unreadCounts: [String?: Int]
    let showCategoryTabs: Bool
    let isOutboxSelected: Bool
    let outboxEmails: [Email]
    let hasMorePages: Bool
    let isLoadingMore: Bool
    let isSyncing: Bool
    let errorMessage: String?
    let searchQuery: String
    let isSearching: Bool
    let accountColorProvider: (VaultMailFeature.Thread) -> Color?

    // Actions
    let onLoadMore: () -> Void
    let onArchive: (VaultMailFeature.Thread) -> Void
    let onDelete: (VaultMailFeature.Thread) -> Void
    let onToggleRead: (VaultMailFeature.Thread) -> Void
    let onToggleStar: (VaultMailFeature.Thread) -> Void
    let onMoveToFolder: (VaultMailFeature.Thread) -> Void
    let onReply: (String) -> Void
    let onReplyAll: (String) -> Void
    let onForward: (String) -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            if showCategoryTabs {
                categorySegmentedControl
                Divider()
            }

            contentBody
        }
    }

    // MARK: - Category Control

    private var categorySegmentedControl: some View {
        CategoryTabBar(
            selectedCategory: $selectedCategory,
            unreadCounts: unreadCounts
        )
    }

    // MARK: - Content Body

    @ViewBuilder
    private var contentBody: some View {
        let trimmedSearch = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearchMode = !trimmedSearch.isEmpty

        if isSearchMode {
            if isSearching {
                VStack {
                    Spacer()
                    ProgressView("Searching emails...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if threads.isEmpty {
                ContentUnavailableView.search(text: trimmedSearch)
            } else {
                threadList
            }
        } else {
            switch viewState {
            case .loading:
                VStack {
                    Spacer()
                    ProgressView("Loading emails...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .loaded:
                threadList

            case .empty:
                ContentUnavailableView(
                    "No Emails",
                    systemImage: "tray",
                    description: Text("Emails you receive will appear here.")
                )

            case .emptyFiltered:
                ContentUnavailableView {
                    Label("No Emails in This Category", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Try selecting a different category.")
                } actions: {
                    Button("Show All") { selectedCategory = nil }
                }

            case .error(let msg):
                ContentUnavailableView {
                    Label("Something Went Wrong", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(msg)
                } actions: {
                    Button("Retry") { onLoadMore() }
                }

            case .offline:
                ContentUnavailableView(
                    "You're Offline",
                    systemImage: "wifi.slash",
                    description: Text("Check your internet connection.")
                )
            }
        }
    }

    // MARK: - Thread List

    private var threadList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Sync progress
                if isSyncing {
                    HStack(spacing: theme.spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Syncing…").font(theme.typography.bodyMedium).foregroundStyle(theme.colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, theme.spacing.lg)
                    .padding(.vertical, theme.spacing.sm)
                    .background(theme.colors.accent.opacity(0.05))
                }

                // Error banner
                if let errorMessage {
                    HStack(spacing: theme.spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.colors.warning)
                        Text(errorMessage).font(theme.typography.bodyMedium).lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, theme.spacing.lg)
                    .padding(.vertical, theme.spacing.xs)
                    .background(theme.colors.warning.opacity(0.1))
                }

                // Outbox or regular threads
                if isOutboxSelected {
                    ForEach(outboxEmails, id: \.id) { email in
                        OutboxRowView(email: email, onRetry: {}, onCancel: {})
                            .padding(.horizontal, theme.spacing.lg)
                        Divider().padding(.leading, theme.spacing.xxxl)
                    }
                } else {
                    ForEach(threads, id: \.id) { thread in
                        MacThreadRow(
                            thread: thread,
                            isSelected: selectedThreadID == thread.id,
                            accountColor: accountColorProvider(thread),
                            isMuted: settings.mutedThreadIds.contains(thread.id),
                            onTap: { selectedThreadID = thread.id }
                        )
                        .contextMenu { threadContextMenu(for: thread) }

                        Divider().padding(.leading, theme.spacing.xxxl)
                    }
                }

                // Pagination sentinel
                if hasMorePages {
                    HStack {
                        Spacer()
                        ProgressView().padding(.vertical, theme.spacing.sm)
                        Spacer()
                    }
                    .onAppear { onLoadMore() }
                }
            }
        }
        .background(theme.colors.background)
        .accessibilityLabel("Email threads")
    }

    // MARK: - Context Menu (FR-MAC-05)

    @ViewBuilder
    private func threadContextMenu(for thread: VaultMailFeature.Thread) -> some View {
        Button { onReply(thread.id) } label: {
            Label("Reply", systemImage: "arrowshape.turn.up.left")
        }
        Button { onReplyAll(thread.id) } label: {
            Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
        }
        Button { onForward(thread.id) } label: {
            Label("Forward", systemImage: "arrowshape.turn.up.right")
        }

        Divider()

        Button { onArchive(thread) } label: {
            Label("Archive", systemImage: "archivebox")
        }
        Button(role: .destructive) { onDelete(thread) } label: {
            Label("Delete", systemImage: "trash")
        }
        Button { onMoveToFolder(thread) } label: {
            Label("Move to Folder…", systemImage: "folder")
        }

        Divider()

        Button { onToggleRead(thread) } label: {
            Label(
                thread.unreadCount > 0 ? "Mark as Read" : "Mark as Unread",
                systemImage: thread.unreadCount > 0 ? "envelope.open" : "envelope"
            )
        }
        Button { onToggleStar(thread) } label: {
            Label(
                thread.isStarred ? "Unstar" : "Star",
                systemImage: thread.isStarred ? "star.slash" : "star"
            )
        }
    }
}

// MARK: - Mac Thread Row (hover + selection)

/// Wrapper that adds hover highlight and themed selection background to thread rows on macOS.
private struct MacThreadRow: View {
    let thread: VaultMailFeature.Thread
    let isSelected: Bool
    var accountColor: Color? = nil
    var isMuted: Bool = false
    let onTap: () -> Void

    @Environment(ThemeProvider.self) private var theme
    @State private var isHovered = false

    var body: some View {
        ThreadRowView(
            thread: thread,
            accountColor: accountColor,
            isMuted: isMuted
        )
        .padding(.horizontal, theme.spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            theme.colors.surfaceSelected
        } else if isHovered {
            theme.colors.surfaceHovered
        } else {
            Color.clear
        }
    }
}
#endif
