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

    // MARK: - Thread List

    private var threadList: some View {
        List(selection: $selectedThreadID) {
            // Sync progress
            if isSyncing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Syncing…").font(.subheadline).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.accentColor.opacity(0.05))
            }

            // Error banner
            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(errorMessage).font(.subheadline).lineLimit(2)
                    Spacer()
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.orange.opacity(0.1))
            }

            // Outbox or regular threads
            if isOutboxSelected {
                ForEach(outboxEmails, id: \.id) { email in
                    OutboxRowView(email: email, onRetry: {}, onCancel: {})
                }
            } else {
                ForEach(threads, id: \.id) { thread in
                    ThreadRowView(
                        thread: thread,
                        accountColor: accountColorProvider(thread)
                    )
                    .tag(thread.id)
                    .contextMenu { threadContextMenu(for: thread) }
                }
            }

            // Pagination sentinel
            if hasMorePages {
                HStack {
                    Spacer()
                    ProgressView().padding(.vertical, 8)
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .onAppear { onLoadMore() }
            }
        }
        .listStyle(.plain)
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
#endif
