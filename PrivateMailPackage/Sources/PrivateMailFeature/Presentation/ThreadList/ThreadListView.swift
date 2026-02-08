import SwiftUI
import SwiftData

/// Main thread list screen displaying paginated email threads.
///
/// Receives use cases as `let` properties (MV pattern, no ViewModels).
/// Manages all view state via `@State` properties and loads data
/// using `.task` for automatic lifecycle-tied async work.
///
/// Features:
/// - Account-specific or unified inbox
/// - AI category filtering via CategoryTabBar
/// - Cursor-based pagination with sentinel row
/// - Pull-to-refresh
/// - Multi-select mode (placeholder)
/// - Swipe actions for archive/delete
/// - Navigation to email detail, compose, search, settings
///
/// Spec ref: Thread List FR-TL-01..05
struct ThreadListView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext

    let fetchThreads: FetchThreadsUseCaseProtocol
    let manageThreadActions: ManageThreadActionsUseCaseProtocol
    let manageAccounts: ManageAccountsUseCaseProtocol
    let syncEmails: SyncEmailsUseCaseProtocol

    // MARK: - View State

    enum ViewState: Equatable {
        case loading
        case loaded
        case empty
        case emptyFiltered
        case error(String)
        case offline

        static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading),
                 (.loaded, .loaded),
                 (.empty, .empty),
                 (.emptyFiltered, .emptyFiltered),
                 (.offline, .offline):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @State private var viewState: ViewState = .loading
    @State private var threads: [PrivateMailFeature.Thread] = []
    @State private var paginationCursor: Date? = nil
    @State private var hasMorePages = false
    @State private var isLoadingMore = false

    // Account & folder selection
    @State private var accounts: [Account] = []
    @State private var selectedAccount: Account? = nil
    @State private var folders: [Folder] = []
    @State private var selectedFolder: Folder? = nil

    // Category filtering
    @State private var selectedCategory: String? = nil
    @State private var unreadCounts: [String?: Int] = [:]

    // Compose sheet
    @State private var showComposer = false

    // Multi-select mode (placeholder for future integration)
    @State private var isMultiSelectMode = false
    @State private var selectedThreadIds: Set<String> = []

    // Account switcher sheet
    @State private var showAccountSwitcher = false

    // Inline error banner (Comment 3: show banner when threads already loaded)
    @State private var errorBannerMessage: String? = nil

    // Outbox emails (Comment 6: display outbox with OutboxRowView)
    @State private var outboxEmails: [Email] = []

    // Category per folder (Comment 9: persist selected category per folder)
    @State private var categoryPerFolder: [String: String?] = [:]

    // Pagination error (Comment 10: inline retry on pagination failure)
    @State private var paginationError: Bool = false

    // Move-to-folder sheet for multi-select (Comment 7)
    @State private var showMoveSheet = false

    // MARK: - Derived State

    /// Whether the selected folder is the virtual Outbox.
    private var isOutboxSelected: Bool {
        guard let folder = selectedFolder else { return false }
        return FolderType(rawValue: folder.folderType) == nil && folder.name == "Outbox"
    }

    /// Navigation title based on selected folder.
    private var navigationTitle: String {
        if selectedAccount == nil {
            return "All Inboxes"
        }
        return selectedFolder?.name ?? "Inbox"
    }

    /// Whether to show category tabs (hidden for Outbox, when no categories visible,
    /// or when AI categorization hasn't been applied to any thread).
    private var showCategoryTabs: Bool {
        guard !isOutboxSelected else { return false }
        let hasVisibleCategories = settings.categoryTabVisibility.values.contains(true)
        // Hide when AI categorization hasn't been applied to any thread
        let uncategorizedRaw = AICategory.uncategorized.rawValue
        let hasAICategorizedThreads = threads.contains {
            guard let cat = $0.aiCategory else { return false }
            return cat != uncategorizedRaw
        }
        return hasVisibleCategories && hasAICategorizedThreads
    }

    /// Account color for unified mode (for thread row indicators).
    private func accountColor(for thread: PrivateMailFeature.Thread) -> Color? {
        guard selectedAccount == nil, accounts.count > 1 else { return nil }
        // Deterministic color from account ID
        return AvatarView.color(for: thread.accountId)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category tab bar
                if showCategoryTabs {
                    CategoryTabBar(
                        selectedCategory: $selectedCategory,
                        unreadCounts: unreadCounts
                    )
                }

                // Main content
                contentView
            }
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar { toolbarContent }
            .sheet(isPresented: $showComposer) {
                ComposerPlaceholder(fromAccount: selectedAccount?.email)
            }
            .sheet(isPresented: $showAccountSwitcher) {
                AccountSwitcherSheet(
                    accounts: accounts,
                    selectedAccountId: selectedAccount?.id,
                    onSelectAccount: { accountId in
                        if let accountId {
                            if let account = accounts.first(where: { $0.id == accountId }) {
                                selectedAccount = account
                                selectedCategory = nil
                                Task { await switchToAccount(account) }
                            }
                        } else {
                            selectedAccount = nil
                            selectedFolder = nil
                            selectedCategory = nil
                            Task { await reloadThreads() }
                        }
                    }
                )
            }
        }
        .task {
            await initialLoad()
        }
        .onChange(of: selectedCategory) {
            Task { await reloadThreads() }
        }
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        switch viewState {
        case .loading:
            loadingView

        case .loaded:
            threadListView

        case .empty:
            emptyStateView

        case .emptyFiltered:
            emptyFilteredView

        case .error(let message):
            errorView(message: message)

        case .offline:
            offlineView
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading emails...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading emails")
    }

    // MARK: - Thread List

    private var threadListView: some View {
        ZStack(alignment: .bottom) {
            threadListContent
            multiSelectOverlay
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveToFolderSheet(folders: folders) { folderId in
                Task { await batchMove(toFolderId: folderId) }
            }
        }
    }

    @ViewBuilder
    private var threadListContent: some View {
        List {
            errorBannerRow
            threadOrOutboxRows
            paginationRow
        }
        .listStyle(.plain)
        .refreshable {
            errorBannerMessage = nil
            // Sync current folder from IMAP, then reload from SwiftData
            if let accountId = selectedAccount?.id, let folderId = selectedFolder?.id {
                do {
                    try await syncEmails.syncFolder(accountId: accountId, folderId: folderId)
                } catch {
                    errorBannerMessage = "Sync failed: \(error.localizedDescription)"
                }
            }
            await reloadThreads()
        }
        .navigationDestination(for: String.self) { threadId in
            if let thread = threads.first(where: { $0.id == threadId }) {
                EmailDetailPlaceholder(threadSubject: thread.subject)
            }
        }
        .accessibilityLabel("Email threads")
    }

    @ViewBuilder
    private var errorBannerRow: some View {
        // Comment 3: Inline error banner when threads are already loaded
        if let errorBannerMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(errorBannerMessage)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer()
                Button {
                    self.errorBannerMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.orange.opacity(0.1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error: \(errorBannerMessage)")
        }
    }

    @ViewBuilder
    private var threadOrOutboxRows: some View {
        // Comment 6: Show outbox rows when outbox folder is selected
        if isOutboxSelected {
            ForEach(outboxEmails, id: \.id) { email in
                OutboxRowView(
                    email: email,
                    onRetry: {
                        // TODO: Retry sending via SendQueueUseCase when sync layer is built
                    },
                    onCancel: {
                        // TODO: Cancel sending via SendQueueUseCase when sync layer is built
                    }
                )
            }
        } else {
            ForEach(threads, id: \.id) { thread in
                threadRow(for: thread)
                // TODO: Add swipe actions for read/unread toggle, star, move (Phase 6 integration)
            }
        }
    }

    @ViewBuilder
    private func threadRow(for thread: PrivateMailFeature.Thread) -> some View {
        if isMultiSelectMode {
            // In multi-select mode, tapping toggles selection instead of navigating
            Button {
                toggleThreadSelection(thread.id)
            } label: {
                ThreadRowView(
                    thread: thread,
                    isMultiSelectMode: isMultiSelectMode,
                    isSelected: selectedThreadIds.contains(thread.id),
                    accountColor: accountColor(for: thread)
                )
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: thread.id) {
                ThreadRowView(
                    thread: thread,
                    isMultiSelectMode: isMultiSelectMode,
                    isSelected: selectedThreadIds.contains(thread.id),
                    accountColor: accountColor(for: thread)
                )
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    Task { await archiveThread(thread) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(.blue)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    Task { await deleteThread(thread) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            // Comment 7: Long-press to enter multi-select mode
            .onLongPressGesture {
                isMultiSelectMode = true
                selectedThreadIds.insert(thread.id)
            }
        }
    }

    @ViewBuilder
    private var paginationRow: some View {
        // Comment 10: Pagination sentinel with inline retry on failure
        if paginationError {
            Button {
                paginationError = false
                Task { await loadMoreThreads() }
            } label: {
                HStack {
                    Spacer()
                    Text("Tap to retry")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
            }
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
        } else if hasMorePages {
            HStack {
                Spacer()
                ProgressView()
                    .padding(.vertical, 8)
                Spacer()
            }
            .listRowSeparator(.hidden)
            .onAppear {
                Task { await loadMoreThreads() }
            }
        }
    }

    @ViewBuilder
    private var multiSelectOverlay: some View {
        // Comment 7: Multi-select toolbar overlay
        if isMultiSelectMode {
            MultiSelectToolbar(
                selectedCount: selectedThreadIds.count,
                onArchive: {
                    Task { await batchArchive() }
                },
                onDelete: {
                    Task { await batchDelete() }
                },
                onMarkRead: {
                    Task { await batchMarkRead() }
                },
                onMarkUnread: {
                    Task { await batchMarkUnread() }
                },
                onStar: {
                    Task { await batchStar() }
                },
                onMove: {
                    showMoveSheet = true
                }
            )
        }
    }

    // MARK: - Empty States

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No emails yet")
                .font(.title3.bold())
            Text("Emails you receive will appear here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No emails. Emails you receive will appear here.")
    }

    private var emptyFilteredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No emails in this category")
                .font(.title3.bold())
            Text("Try selecting a different category")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Show All") {
                selectedCategory = nil
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No emails in this category. Try selecting a different category.")
    }

    // MARK: - Error & Offline Views

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") {
                Task { await reloadThreads() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message). Tap retry to try again.")
    }

    private var offlineView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("You're offline")
                .font(.title3.bold())
            Text("Check your internet connection and try again")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await reloadThreads() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You are offline. Check your connection and try again.")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            // Folders button
            // TODO: Replace with navigation to FolderListView (Phase 6 integration)
            Menu {
                if folders.isEmpty {
                    Text("No folders")
                } else {
                    ForEach(folders, id: \.id) { folder in
                        Button {
                            selectFolder(folder)
                        } label: {
                            Label(folder.name, systemImage: folderIcon(for: folder))
                        }
                    }
                }
            } label: {
                Label("Folders", systemImage: "folder")
            }
            .accessibilityLabel("Folders")
        }

        ToolbarItemGroup(placement: .automatic) {
            // Account switcher
            Button {
                showAccountSwitcher = true
            } label: {
                Label("Account", systemImage: "person.circle")
            }
            .accessibilityLabel("Switch account")

            // Search
            NavigationLink {
                SearchPlaceholder()
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .accessibilityLabel("Search emails")

            // Compose
            Button {
                showComposer = true
            } label: {
                Label("Compose", systemImage: "square.and.pencil")
            }
            .accessibilityLabel("Compose new email")

            // Settings
            NavigationLink {
                SettingsView(manageAccounts: manageAccounts)
            } label: {
                Label("Settings", systemImage: "gear")
            }
            .accessibilityLabel("Settings")
        }

        // Multi-select cancel button
        if isMultiSelectMode {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    isMultiSelectMode = false
                    selectedThreadIds.removeAll()
                }
            }
        }
    }

    // MARK: - Data Loading

    /// Initial load on view appear: show cached data instantly, then sync in background.
    ///
    /// Two-phase approach avoids blocking the UI while IMAP sync completes:
    /// 1. Load accounts, folders, and cached threads from SwiftData (instant).
    /// 2. Fire IMAP sync in the background; reload on completion.
    private func initialLoad() async {
        viewState = .loading

        do {
            // Phase 1: Load cached data from SwiftData (instant)
            accounts = try await manageAccounts.getAccounts()

            guard let firstAccount = accounts.first else {
                viewState = .empty
                return
            }

            selectedAccount = firstAccount

            // Load folders for the selected account
            folders = try await fetchThreads.fetchFolders(accountId: firstAccount.id)

            // Select inbox folder by default
            let inboxType = FolderType.inbox.rawValue
            selectedFolder = folders.first(where: { $0.folderType == inboxType }) ?? folders.first

            // Show cached threads immediately (may be empty on first launch)
            await loadThreadsAndCounts()

            // Phase 2: Sync from IMAP in the background, then refresh the view
            NSLog("[UI] Starting background sync for account: \(firstAccount.id)")
            Task {
                do {
                    try await syncEmails.syncAccount(accountId: firstAccount.id)
                    NSLog("[UI] Background sync succeeded, reloading threads...")
                    // Sync succeeded — reload folders and threads with fresh data
                    folders = try await fetchThreads.fetchFolders(accountId: firstAccount.id)
                    if selectedFolder == nil {
                        let inboxType = FolderType.inbox.rawValue
                        selectedFolder = folders.first(where: { $0.folderType == inboxType }) ?? folders.first
                    }
                    await loadThreadsAndCounts()
                    NSLog("[UI] Threads reloaded, count: \(threads.count)")
                } catch {
                    NSLog("[UI] Background sync FAILED: \(error)")
                    errorBannerMessage = "Sync failed: \(error.localizedDescription)"
                }
            }
        } catch {
            viewState = .error(error.localizedDescription)
        }
    }

    /// Reload threads for current account/folder/category selection.
    private func reloadThreads() async {
        viewState = .loading
        threads = []
        paginationCursor = nil
        hasMorePages = false
        await loadThreadsAndCounts()
    }

    /// Load threads and unread counts for the current selection.
    private func loadThreadsAndCounts() async {
        do {
            let page: ThreadPage
            let counts: [String?: Int]

            if let account = selectedAccount, let folder = selectedFolder {
                // Account-specific fetch
                page = try await fetchThreads.fetchThreads(
                    accountId: account.id,
                    folderId: folder.id,
                    category: selectedCategory,
                    cursor: nil,
                    pageSize: AppConstants.threadListPageSize
                )
                counts = try await fetchThreads.fetchUnreadCounts(
                    accountId: account.id,
                    folderId: folder.id
                )
            } else {
                // Unified inbox fetch
                page = try await fetchThreads.fetchUnifiedThreads(
                    category: selectedCategory,
                    cursor: nil,
                    pageSize: AppConstants.threadListPageSize
                )
                counts = try await fetchThreads.fetchUnreadCountsUnified()
            }

            threads = page.threads
            paginationCursor = page.nextCursor
            hasMorePages = page.hasMore
            unreadCounts = counts

            if threads.isEmpty {
                viewState = selectedCategory != nil ? .emptyFiltered : .empty
            } else {
                viewState = .loaded
            }
        } catch {
            // Comment 3: If we already have threads, show inline error banner
            if !threads.isEmpty {
                errorBannerMessage = error.localizedDescription
                viewState = .loaded
            } else {
                viewState = .error(error.localizedDescription)
            }
        }
    }

    /// Load more threads for pagination.
    private func loadMoreThreads() async {
        guard hasMorePages, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let page: ThreadPage

            if let account = selectedAccount, let folder = selectedFolder {
                page = try await fetchThreads.fetchThreads(
                    accountId: account.id,
                    folderId: folder.id,
                    category: selectedCategory,
                    cursor: paginationCursor,
                    pageSize: AppConstants.threadListPageSize
                )
            } else {
                page = try await fetchThreads.fetchUnifiedThreads(
                    category: selectedCategory,
                    cursor: paginationCursor,
                    pageSize: AppConstants.threadListPageSize
                )
            }

            threads.append(contentsOf: page.threads)
            paginationCursor = page.nextCursor
            hasMorePages = page.hasMore
        } catch {
            // Comment 10: Show inline retry instead of silently stopping
            paginationError = true
        }
    }

    /// Switch to a specific account: load its folders and threads.
    private func switchToAccount(_ account: Account) async {
        do {
            folders = try await fetchThreads.fetchFolders(accountId: account.id)
            let inboxType = FolderType.inbox.rawValue
            selectedFolder = folders.first(where: { $0.folderType == inboxType }) ?? folders.first
            await reloadThreads()
        } catch {
            viewState = .error(error.localizedDescription)
        }
    }

    // MARK: - Thread Actions

    private func archiveThread(_ thread: PrivateMailFeature.Thread) async {
        do {
            try await manageThreadActions.archiveThread(id: thread.id)
            threads.removeAll { $0.id == thread.id }
            if threads.isEmpty {
                viewState = selectedCategory != nil ? .emptyFiltered : .empty
            }
            // TODO: Show UndoToastView (Phase 6 integration)
        } catch {
            // TODO: Show error toast (Phase 6 integration)
        }
    }

    private func deleteThread(_ thread: PrivateMailFeature.Thread) async {
        do {
            try await manageThreadActions.deleteThread(id: thread.id)
            threads.removeAll { $0.id == thread.id }
            if threads.isEmpty {
                viewState = selectedCategory != nil ? .emptyFiltered : .empty
            }
            // TODO: Show UndoToastView (Phase 6 integration)
        } catch {
            // TODO: Show error toast (Phase 6 integration)
        }
    }

    // MARK: - Folder Selection (Comment 9: persist category per folder)

    /// Switch to a folder, saving and restoring the selected category.
    private func selectFolder(_ folder: Folder) {
        // Save current category for the current folder
        if let currentFolder = selectedFolder {
            categoryPerFolder[currentFolder.id] = selectedCategory
        }
        selectedFolder = folder
        // Restore category for the new folder (or nil if none saved)
        if let saved = categoryPerFolder[folder.id] {
            selectedCategory = saved
        } else {
            selectedCategory = nil
        }
        // Load outbox if needed, otherwise reload threads
        if isOutboxSelected {
            Task { await loadOutboxEmails() }
        } else {
            Task { await reloadThreads() }
        }
    }

    // MARK: - Outbox Loading (Comment 6)

    /// Load outbox emails for the current account.
    private func loadOutboxEmails() async {
        do {
            outboxEmails = try await fetchThreads.fetchOutboxEmails(accountId: selectedAccount?.id)
            viewState = outboxEmails.isEmpty ? .empty : .loaded
        } catch {
            viewState = .error(error.localizedDescription)
        }
    }

    // MARK: - Multi-Select (Comment 7)

    /// Toggle selection of a thread in multi-select mode.
    private func toggleThreadSelection(_ threadId: String) {
        if selectedThreadIds.contains(threadId) {
            selectedThreadIds.remove(threadId)
        } else {
            selectedThreadIds.insert(threadId)
        }
    }

    // MARK: - Batch Actions (Comment 7)

    private func batchArchive() async {
        let ids = Array(selectedThreadIds)
        do {
            try await manageThreadActions.archiveThreads(ids: ids)
            threads.removeAll { ids.contains($0.id) }
            exitMultiSelectMode()
        } catch {
            // TODO: Show error toast
        }
    }

    private func batchDelete() async {
        let ids = Array(selectedThreadIds)
        do {
            try await manageThreadActions.deleteThreads(ids: ids)
            threads.removeAll { ids.contains($0.id) }
            exitMultiSelectMode()
        } catch {
            // TODO: Show error toast
        }
    }

    private func batchMarkRead() async {
        let ids = Array(selectedThreadIds)
        do {
            try await manageThreadActions.markThreadsRead(ids: ids)
            exitMultiSelectMode()
            await reloadThreads()
        } catch {
            // TODO: Show error toast
        }
    }

    private func batchMarkUnread() async {
        let ids = Array(selectedThreadIds)
        do {
            try await manageThreadActions.markThreadsUnread(ids: ids)
            exitMultiSelectMode()
            await reloadThreads()
        } catch {
            // TODO: Show error toast
        }
    }

    private func batchStar() async {
        let ids = Array(selectedThreadIds)
        do {
            try await manageThreadActions.starThreads(ids: ids)
            exitMultiSelectMode()
            await reloadThreads()
        } catch {
            // TODO: Show error toast
        }
    }

    private func batchMove(toFolderId: String) async {
        let ids = Array(selectedThreadIds)
        do {
            try await manageThreadActions.moveThreads(ids: ids, toFolderId: toFolderId)
            threads.removeAll { ids.contains($0.id) }
            exitMultiSelectMode()
        } catch {
            // TODO: Show error toast
        }
    }

    private func exitMultiSelectMode() {
        isMultiSelectMode = false
        selectedThreadIds.removeAll()
        if threads.isEmpty {
            viewState = selectedCategory != nil ? .emptyFiltered : .empty
        }
    }

    // MARK: - Helpers

    /// Icon for a folder based on its type.
    private func folderIcon(for folder: Folder) -> String {
        guard let folderType = FolderType(rawValue: folder.folderType) else {
            return "folder"
        }
        switch folderType {
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
