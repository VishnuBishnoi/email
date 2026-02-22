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
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.modelContext) private var modelContext

    let fetchThreads: FetchThreadsUseCaseProtocol
    let manageThreadActions: ManageThreadActionsUseCaseProtocol
    let manageAccounts: ManageAccountsUseCaseProtocol
    let syncEmails: SyncEmailsUseCaseProtocol
    let fetchEmailDetail: FetchEmailDetailUseCaseProtocol
    let markRead: MarkReadUseCaseProtocol
    let downloadAttachment: DownloadAttachmentUseCaseProtocol
    let composeEmail: ComposeEmailUseCaseProtocol
    let queryContacts: QueryContactsUseCaseProtocol
    let idleMonitor: IDLEMonitorUseCaseProtocol?
    var modelManager: ModelManager = ModelManager()
    var aiEngineResolver: AIEngineResolver?
    var aiProcessingQueue: AIProcessingQueue?
    var summarizeThread: SummarizeThreadUseCaseProtocol?
    var smartReply: SmartReplyUseCaseProtocol?
    var searchUseCase: SearchEmailsUseCase?
    var providerDiscovery: ProviderDiscovery?
    var connectionTestUseCase: ConnectionTestUseCaseProtocol?

    @Environment(UndoSendManager.self) private var undoSendManager
    @Environment(NotificationSyncCoordinator.self) private var notificationCoordinator

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
    @State private var threads: [VaultMailFeature.Thread] = []
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
    @State private var composerMode: ComposerMode? = nil

    // Multi-select mode (placeholder for future integration)
    @State private var isMultiSelectMode = false
    @State private var selectedThreadIds: Set<String> = []

    // Account switcher sheet
    @State private var showAccountSwitcher = false

    // Inline error banner (Comment 3: show banner when threads already loaded)
    @State private var errorBannerMessage: String? = nil

    // Action toast (undo feedback for archive/delete)
    @State private var actionToastMessage: String? = nil
    @State private var actionToastUndoInfo: (threadId: String, folderId: String)? = nil

    // Error toast (feedback for failed thread actions)
    @State private var errorToastMessage: String? = nil

    // Background sync progress feedback
    @State private var isSyncing = false

    // Outbox emails (Comment 6: display outbox with OutboxRowView)
    @State private var outboxEmails: [Email] = []

    // Category per folder (Comment 9: persist selected category per folder)
    @State private var categoryPerFolder: [String: String?] = [:]

    // Pagination error (Comment 10: inline retry on pagination failure)
    @State private var paginationError: Bool = false

    // Move-to-folder sheet for multi-select (Comment 7)
    @State private var showMoveSheet = false

    // IMAP IDLE monitoring task (FR-SYNC-03 real-time updates)
    @State private var idleTask: Task<Void, Never>?

    // Background sync task — stored so it can be cancelled on timeout or disappear
    @State private var syncTask: Task<Void, Never>?

    // Tracks elapsed sync time for showing "taking longer than expected" + cancel
    @State private var syncElapsedSeconds: Int = 0

    // Programmatic navigation for bottom tab bar
    @State private var navigationPath = NavigationPath()

    // Inline search (Apple Mail style — FR-SEARCH-01)
    @State private var isSearchActive = false
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var searchThreads: [VaultMailFeature.Thread] = []
    @State private var searchViewState: SearchViewState = .idle
    @State private var searchFilters = SearchFilters()
    @State private var isCurrentFolderScope = false
    @State private var recentSearches: [String] = []

    private let recentSearchesKey = "recentSearches"
    private let maxRecentSearches = 10

    /// Destinations triggered from the bottom tab bar.
    enum TabDestination: Hashable {
        case settings
        case aiChat
    }

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
    private func accountColor(for thread: VaultMailFeature.Thread) -> Color? {
        guard selectedAccount == nil, accounts.count > 1 else { return nil }
        // Deterministic color from account ID
        return AvatarView.color(for: thread.accountId)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Category tab bar (hidden during search)
                    if showCategoryTabs && !isSearchActive {
                        CategoryTabBar(
                            selectedCategory: $selectedCategory,
                            unreadCounts: unreadCounts
                        )
                    }

                    // Main content
                    contentView
                }

                // Undo-send overlay (FR-COMP-02)
                if undoSendManager.isCountdownActive {
                    UndoSendToastView(
                        remainingSeconds: undoSendManager.remainingSeconds,
                        onUndo: {
                            if let emailId = undoSendManager.undoSend() {
                                Task {
                                    try? await composeEmail.undoSend(emailId: emailId)
                                    // TODO: Reopen composer with draft content
                                }
                            }
                        }
                    )
                    .animation(.easeInOut(duration: 0.3), value: undoSendManager.isCountdownActive)
                }

                // Action undo toast (archive/delete feedback)
                if let msg = actionToastMessage {
                    UndoToastView(
                        message: msg,
                        onUndo: { undoLastAction() },
                        onDismiss: { withAnimation { actionToastMessage = nil; actionToastUndoInfo = nil } }
                    )
                    .animation(.easeInOut(duration: 0.3), value: actionToastMessage)
                }

                // Error toast (failed action feedback)
                if let msg = errorToastMessage {
                    ErrorToastView(
                        message: msg,
                        onDismiss: { withAnimation { errorToastMessage = nil } }
                    )
                    .animation(.easeInOut(duration: 0.3), value: errorToastMessage)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isMultiSelectMode && !isSearchActive {
                    BottomTabBar(
                        folders: folders,
                        onSelectFolder: { folder in selectFolder(folder) },
                        onAccountTap: { showAccountSwitcher = true },
                        onSearchTap: { isSearchActive = true },
                        onComposeTap: {
                            let accountId = selectedAccount?.id ?? accounts.first?.id ?? ""
                            composerMode = .new(accountId: accountId)
                        },
                        onSettingsTap: { navigationPath.append(TabDestination.settings) }
                    )
                }
            }
            .navigationTitle(isSearchActive ? "" : navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(isSearchActive ? .inline : .large)
            #endif
            .toolbar {
                if isMultiSelectMode {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isMultiSelectMode = false
                            selectedThreadIds.removeAll()
                        }
                    }
                }
            }
            .navigationDestination(for: TabDestination.self) { destination in
                tabDestinationView(for: destination)
            }
            .navigationDestination(for: String.self) { threadId in
                EmailDetailView(
                    threadId: threadId,
                    fetchEmailDetail: fetchEmailDetail,
                    markRead: markRead,
                    manageThreadActions: manageThreadActions,
                    downloadAttachment: downloadAttachment,
                    summarizeThread: summarizeThread,
                    smartReply: smartReply,
                    composeEmail: composeEmail,
                    queryContacts: queryContacts,
                    accounts: accounts
                )
            }
            .sheet(item: $composerMode) { mode in
                composerSheet(for: mode)
            }
            .sheet(isPresented: $showAccountSwitcher) {
                accountSwitcherSheet
            }
        }
        .task {
            await initialLoad()
        }
        .onChange(of: navigationPath) { oldPath, newPath in
            // Refresh accounts when user pops back from Settings (or any pushed screen).
            // Without this, accounts added in Settings won't appear in the switcher
            // until the app is relaunched.
            if newPath.count < oldPath.count {
                Task { await refreshAccounts() }
            }
        }
        .onChange(of: selectedCategory) {
            Task { await reloadThreads() }
        }
        .onChange(of: selectedFolder?.id) {
            // Restart IDLE when user changes folder — but NOT during initial sync,
            // where the sync task starts IDLE after completion.
            guard !isSyncing else { return }
            startIDLEMonitor()
        }
        .onChange(of: notificationCoordinator.pendingThreadNavigation) { _, threadId in
            // Deep link: navigate to thread when user taps a notification (NOTIF-17)
            if let threadId {
                notificationCoordinator.pendingThreadNavigation = nil
                navigationPath.append(threadId)
            }
        }
        .onDisappear {
            stopIDLEMonitor()
            syncTask?.cancel()
            syncTask = nil
        }
        .task(id: isSyncing) {
            // Tick elapsed seconds while sync is active (for progress feedback)
            guard isSyncing else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                syncElapsedSeconds += 1
            }
        }
        .task(id: SearchDebounceTrigger(text: searchText, filters: searchFilters, isCurrentFolderScope: isCurrentFolderScope)) {
            guard isSearchActive else { return }
            // 300ms debounce via task cancellation (FR-SEARCH-01)
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearch()
        }
        .onChange(of: isSearchActive) { _, newValue in
            if !newValue {
                // Reset search state when dismissed
                searchText = ""
                searchResults = []
                searchThreads = []
                searchViewState = .idle
                searchFilters = SearchFilters()
                isCurrentFolderScope = false
            } else {
                loadRecentSearches()
            }
        }
    }

    // MARK: - Extracted Sheets & Destinations

    @ViewBuilder
    private func tabDestinationView(for destination: TabDestination) -> some View {
        switch destination {
        case .settings:
            SettingsView(manageAccounts: manageAccounts, modelManager: modelManager, aiEngineResolver: aiEngineResolver, providerDiscovery: providerDiscovery, connectionTestUseCase: connectionTestUseCase)
                .onDisappear {
                    Task { await refreshAccounts() }
                }
        case .aiChat:
            if let resolver = aiEngineResolver {
                AIChatView(engineResolver: resolver)
            } else {
                Text("AI not available")
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func composerSheet(for mode: ComposerMode) -> some View {
        ComposerView(
            composeEmail: composeEmail,
            queryContacts: queryContacts,
            smartReply: smartReply ?? SmartReplyUseCase(aiRepository: StubAIRepository()),
            mode: mode,
            accounts: accounts,
            initialBody: nil,
            onDismiss: { result in
                composerMode = nil
                handleComposerDismiss(result)
            }
        )
        .environment(settings)
    }

    @ViewBuilder
    private var accountSwitcherSheet: some View {
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
                    selectedCategory = nil
                    folders = buildUnifiedFolders()
                    let inboxType = FolderType.inbox.rawValue
                    selectedFolder = folders.first(where: { $0.folderType == inboxType }) ?? folders.first
                    Task { await reloadThreads() }
                }
            }
        )
    }

    // MARK: - Content View

    @ViewBuilder
    private var contentView: some View {
        if isSearchActive {
            SearchContentView(
                searchText: $searchText,
                viewState: searchViewState,
                filters: $searchFilters,
                isCurrentFolderScope: $isCurrentFolderScope,
                currentFolderName: selectedFolder?.name,
                threads: searchThreads,
                searchResults: searchResults,
                recentSearches: recentSearches,
                onSelectRecentSearch: { query in
                    searchText = query
                },
                onClearRecentSearches: {
                    recentSearches = []
                    UserDefaults.standard.removeObject(forKey: recentSearchesKey)
                },
                onDismiss: {
                    isSearchActive = false
                }
            )
        } else {
            threadListContentView
        }
    }

    @ViewBuilder
    private var threadListContentView: some View {
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
        VStack(spacing: theme.spacing.md) {
            ProgressView()
                .controlSize(.large)
            Text("Loading emails...")
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textSecondary)
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
            syncProgressRow
            errorBannerRow
            threadOrOutboxRows
            paginationRow
        }
        .listStyle(.plain)
        .refreshable {
            errorBannerMessage = nil
            // Sync current folder from IMAP, then reload from SwiftData
            var syncedEmails: [Email] = []
            if let accountId = selectedAccount?.id, let folderId = selectedFolder?.id {
                do {
                    syncedEmails = try await syncEmails.syncFolder(accountId: accountId, folderId: folderId)
                } catch {
                    errorBannerMessage = "Sync failed: \(error.localizedDescription)"
                }
            }
            await reloadThreads()
            runAIClassification(for: syncedEmails)
            // Notify notification coordinator about pull-to-refresh emails (NOTIF-03)
            await notificationCoordinator.didSyncNewEmails(
                syncedEmails,
                fromBackground: false
            )
        }
        .accessibilityLabel("Email threads")
    }

    @ViewBuilder
    private var syncProgressRow: some View {
        if isSyncing && !threads.isEmpty {
            HStack(spacing: theme.spacing.listRowSpacing) {
                ProgressView()
                    .controlSize(.small)
                Text(syncElapsedSeconds >= 15 ? "Still syncing…" : "Syncing…")
                    .font(theme.typography.bodyMedium)
                    .foregroundStyle(theme.colors.textSecondary)
                Spacer()
                if syncElapsedSeconds >= 15 {
                    Button("Cancel") {
                        syncTask?.cancel()
                        syncTask = nil
                        isSyncing = false
                        syncElapsedSeconds = 0
                    }
                    .font(theme.typography.bodyMedium)
                    .foregroundStyle(theme.colors.textSecondary)
                }
            }
            .padding(.vertical, theme.spacing.xs)
            .listRowBackground(theme.colors.accentMuted)
            .accessibilityLabel("Syncing mailbox")
        }
    }

    @ViewBuilder
    private var errorBannerRow: some View {
        // Comment 3: Inline error banner when threads are already loaded
        if let errorBannerMessage {
            HStack(spacing: theme.spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.colors.warning)
                Text(errorBannerMessage)
                    .font(theme.typography.bodyMedium)
                    .lineLimit(2)
                Spacer()
                Button {
                    self.errorBannerMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, theme.spacing.xs)
            .listRowBackground(theme.colors.warningMuted)
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
                // Swipe actions (read/unread, star) are on the threadRow view builder
            }
        }
    }

    @ViewBuilder
    private func threadRow(for thread: VaultMailFeature.Thread) -> some View {
        if isMultiSelectMode {
            // In multi-select mode, tapping toggles selection instead of navigating
            Button {
                toggleThreadSelection(thread.id)
            } label: {
                ThreadRowView(
                    thread: thread,
                    isMultiSelectMode: isMultiSelectMode,
                    isSelected: selectedThreadIds.contains(thread.id),
                    accountColor: accountColor(for: thread),
                    isMuted: settings.mutedThreadIds.contains(thread.id)
                )
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: thread.id) {
                ThreadRowView(
                    thread: thread,
                    isMultiSelectMode: isMultiSelectMode,
                    isSelected: selectedThreadIds.contains(thread.id),
                    accountColor: accountColor(for: thread),
                    isMuted: settings.mutedThreadIds.contains(thread.id)
                )
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    Task { await archiveThread(thread) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(theme.colors.accent)

                Button {
                    Task { await toggleReadStatus(thread) }
                } label: {
                    Label(
                        thread.unreadCount > 0 ? "Read" : "Unread",
                        systemImage: thread.unreadCount > 0 ? "envelope.open" : "envelope.badge"
                    )
                }
                .tint(.indigo)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    Task { await deleteThread(thread) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    Task { await toggleStarStatus(thread) }
                } label: {
                    Label(
                        thread.isStarred ? "Unstar" : "Star",
                        systemImage: thread.isStarred ? "star.slash" : "star.fill"
                    )
                }
                .tint(theme.colors.starred)

                Button {
                    settings.toggleMuteThread(threadId: thread.id)
                } label: {
                    Label(
                        settings.mutedThreadIds.contains(thread.id) ? "Unmute" : "Mute",
                        systemImage: settings.mutedThreadIds.contains(thread.id) ? "bell" : "bell.slash"
                    )
                }
                .tint(theme.colors.disabled)
            }
            // Comment 7: Context menu to enter multi-select mode.
            // Note: .onLongPressGesture blocks NavigationLink tap gesture in
            // SwiftUI Lists, so we use .contextMenu instead.
            .contextMenu {
                Button {
                    isMultiSelectMode = true
                    selectedThreadIds.insert(thread.id)
                } label: {
                    Label("Select", systemImage: "checkmark.circle")
                }
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
                        .font(theme.typography.bodyMedium)
                        .foregroundStyle(theme.colors.accent)
                    Spacer()
                }
            }
            .padding(.vertical, theme.spacing.sm)
            .listRowSeparator(.hidden)
        } else if hasMorePages {
            HStack {
                Spacer()
                ProgressView()
                    .padding(.vertical, theme.spacing.sm)
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
        VStack(spacing: theme.spacing.lg) {
            if isSyncing {
                ProgressView()
                    .controlSize(.large)
                Text("Syncing your mailbox…")
                    .font(theme.typography.titleLarge)

                if syncElapsedSeconds < 15 {
                    Text("This may take a moment on first login")
                        .font(theme.typography.bodyMedium)
                        .foregroundStyle(theme.colors.textSecondary)
                } else {
                    Text("Still syncing — this is taking longer than expected")
                        .font(theme.typography.bodyMedium)
                        .foregroundStyle(theme.colors.textSecondary)

                    Button("Cancel Sync") {
                        syncTask?.cancel()
                        syncTask = nil
                        isSyncing = false
                        syncElapsedSeconds = 0
                        viewState = .error("Sync cancelled. Pull to refresh to try again.")
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.colors.textSecondary)
                }
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 48))
                    .foregroundStyle(theme.colors.textSecondary)
                Text("No emails yet")
                    .font(theme.typography.titleLarge)
                Text("Emails you receive will appear here")
                    .font(theme.typography.bodyMedium)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isSyncing ? "Syncing your mailbox" : "No emails. Emails you receive will appear here.")
    }

    private var emptyFilteredView: some View {
        VStack(spacing: theme.spacing.lg) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 48))
                .foregroundStyle(theme.colors.textSecondary)
            Text("No emails in this category")
                .font(theme.typography.titleLarge)
            Text("Try selecting a different category")
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textSecondary)
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
        VStack(spacing: theme.spacing.lg) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(theme.colors.warning)
            Text("Something went wrong")
                .font(theme.typography.titleLarge)
            Text(message)
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") {
                Task { await initialLoad() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message). Tap retry to try again.")
    }

    private var offlineView: some View {
        VStack(spacing: theme.spacing.lg) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(theme.colors.textSecondary)
            Text("You're offline")
                .font(theme.typography.titleLarge)
            Text("Check your internet connection and try again")
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textSecondary)
            Button("Retry") {
                Task { await reloadThreads() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You are offline. Check your connection and try again.")
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

            // Phase 2: Sync from IMAP — inbox first, then remaining folders.
            // The onInboxSynced callback refreshes the UI as soon as inbox is ready,
            // so the user sees their emails without waiting for all folders.
            NSLog("[UI] Starting background sync for account: \(firstAccount.id)")
            isSyncing = true
            syncElapsedSeconds = 0

            let accountId = firstAccount.id
            syncTask = Task {
                defer {
                    isSyncing = false
                    syncElapsedSeconds = 0
                    syncTask = nil
                }
                do {
                    let syncedEmails = try await syncEmails.syncAccountInboxFirst(
                        accountId: accountId,
                        onInboxSynced: { _ in
                            // Inbox synced — reload folders and re-select inbox immediately
                            NSLog("[UI] Inbox synced, refreshing folder list and threads...")
                            if let freshFolders = try? await fetchThreads.fetchFolders(accountId: accountId) {
                                folders = freshFolders
                                let inboxType = FolderType.inbox.rawValue
                                selectedFolder = freshFolders.first(where: { $0.folderType == inboxType }) ?? freshFolders.first
                            }
                            await loadThreadsAndCounts()
                            NSLog("[UI] Inbox threads loaded, count: \(threads.count)")
                        }
                    )
                    guard !Task.isCancelled else { return }
                    NSLog("[UI] Full sync completed, final reload...")

                    // Final reload to pick up emails from all folders
                    folders = try await fetchThreads.fetchFolders(accountId: accountId)
                    // Always re-select folder (SwiftData objects may have changed)
                    let currentFolderType = selectedFolder?.folderType
                    if let currentType = currentFolderType {
                        selectedFolder = folders.first(where: { $0.folderType == currentType }) ?? folders.first
                    } else {
                        let inboxType = FolderType.inbox.rawValue
                        selectedFolder = folders.first(where: { $0.folderType == inboxType }) ?? folders.first
                    }
                    await loadThreadsAndCounts()
                    NSLog("[UI] Threads reloaded, count: \(threads.count)")

                    // Run AI classification on ALL synced emails
                    runAIClassification(for: syncedEmails)

                    // Notify notification coordinator about new emails (NOTIF-03)
                    // Mark first launch complete so subsequent syncs can deliver notifications.
                    // The initial sync emails are suppressed to avoid flooding on first open.
                    notificationCoordinator.markFirstLaunchComplete()
                    await notificationCoordinator.didSyncNewEmails(
                        syncedEmails,
                        fromBackground: false
                    )

                    // Start IMAP IDLE for real-time inbox updates (FR-SYNC-03)
                    startIDLEMonitor()
                } catch is CancellationError {
                    NSLog("[UI] Background sync cancelled")
                } catch {
                    guard !Task.isCancelled else { return }
                    NSLog("[UI] Background sync FAILED: \(error)")
                    if threads.isEmpty {
                        // No cached data — show full-screen error with retry
                        viewState = .error("Sync failed: \(error.localizedDescription)")
                    } else {
                        // Have cached threads — show inline banner
                        errorBannerMessage = "Sync failed: \(error.localizedDescription)"
                    }
                }
            }

            // No hard timeout — the IMAP layer has per-operation timeouts,
            // and the user can cancel via the "Cancel Sync" button that appears
            // after 15 seconds. A hard timeout caused premature cancellation on
            // accounts with many folders during initial sync.
        } catch {
            viewState = .error(error.localizedDescription)
        }
    }

    /// Refresh the accounts list from SwiftData.
    ///
    /// Called when the user returns from Settings so newly added (or removed)
    /// accounts appear immediately in the account-switcher sheet.
    private func refreshAccounts() async {
        do {
            let freshAccounts = try await manageAccounts.getAccounts()
            let oldIds = Set(accounts.map(\.id))
            let newIds = Set(freshAccounts.map(\.id))
            accounts = freshAccounts

            // If the currently selected account was removed, fall back to first
            if let sel = selectedAccount, !newIds.contains(sel.id) {
                if let first = freshAccounts.first {
                    selectedAccount = first
                    await switchToAccount(first)
                } else {
                    selectedAccount = nil
                    viewState = .empty
                }
            }

            // Rebuild unified folders if in "All Accounts" mode
            if selectedAccount == nil {
                folders = buildUnifiedFolders()
            }

            // If a brand-new account was added, kick off background sync for it
            let addedIds = newIds.subtracting(oldIds)
            for addedId in addedIds {
                NSLog("[UI] New account detected: \(addedId), starting background sync")
                Task {
                    do {
                        _ = try await syncEmails.syncAccountInboxFirst(accountId: addedId, onInboxSynced: { _ in })
                    } catch {
                        NSLog("[UI] Background sync for new account \(addedId) failed: \(error)")
                    }
                }
            }
        } catch {
            NSLog("[UI] Failed to refresh accounts: \(error)")
        }
    }

    // MARK: - IMAP IDLE Monitoring (FR-SYNC-03)

    /// Starts monitoring the current folder for new mail via IMAP IDLE.
    ///
    /// On `.newMail` events, triggers an incremental folder sync and reloads threads.
    /// Automatically cancels when the folder/account changes or view disappears.
    private func startIDLEMonitor() {
        // Cancel any existing monitor
        stopIDLEMonitor()

        guard let monitor = idleMonitor,
              let accountId = selectedAccount?.id,
              let folderPath = selectedFolder?.imapPath else {
            return
        }

        NSLog("[IDLE] Starting monitor for \(folderPath)")
        idleTask = Task {
            var retryDelay: Duration = .seconds(2)
            let maxDelay: Duration = .seconds(30)

            while !Task.isCancelled {
                let stream = monitor.monitor(accountId: accountId, folderImapPath: folderPath)
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .newMail:
                        NSLog("[IDLE] New mail notification, syncing folder...")
                        if let folderId = selectedFolder?.id {
                            let syncedEmails = (try? await syncEmails.syncFolder(accountId: accountId, folderId: folderId)) ?? []
                            await loadThreadsAndCounts()
                            runAIClassification(for: syncedEmails)
                            // Notify notification coordinator about IDLE-delivered emails (NOTIF-03)
                            await notificationCoordinator.didSyncNewEmails(
                                syncedEmails,
                                fromBackground: false
                            )
                        }
                        retryDelay = .seconds(2) // reset on success
                    case .disconnected:
                        NSLog("[IDLE] Monitor disconnected, will retry in \(retryDelay)")
                    }
                }

                // Stream ended — retry with exponential backoff
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: retryDelay)
                retryDelay = min(retryDelay * 2, maxDelay)
            }
        }
    }

    /// Stops the IMAP IDLE monitor.
    private func stopIDLEMonitor() {
        idleTask?.cancel()
        idleTask = nil
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
                // Unified inbox fetch — filter by folder type if a folder is selected
                page = try await fetchThreads.fetchUnifiedThreads(
                    category: selectedCategory,
                    folderType: selectedFolder?.folderType,
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
                    folderType: selectedFolder?.folderType,
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

    /// Build a deduplicated folder list for unified "All Accounts" mode.
    ///
    /// Collects folders from every account and keeps the first occurrence of
    /// each `folderType`, so the user sees one "Inbox", one "Sent", etc.
    /// In unified mode the folder selection is cosmetic (thread loading uses
    /// `fetchUnifiedThreads` regardless), but it gives the user a consistent
    /// folder menu rather than stale folders from the last single-account view.
    private func buildUnifiedFolders() -> [Folder] {
        var seenTypes = Set<String>()
        var result: [Folder] = []

        for folder in accounts.flatMap(\.folders) {
            if seenTypes.insert(folder.folderType).inserted {
                result.append(folder)
            }
        }

        return result
    }

    // MARK: - Thread Actions

    private func archiveThread(_ thread: VaultMailFeature.Thread) async {
        do {
            let folderId = selectedFolder?.id ?? ""
            try await manageThreadActions.archiveThread(id: thread.id)
            threads.removeAll { $0.id == thread.id }
            if threads.isEmpty {
                viewState = selectedCategory != nil ? .emptyFiltered : .empty
            }
            await notificationCoordinator.didRemoveThread(threadId: thread.id)
            withAnimation {
                actionToastMessage = "Thread archived"
                actionToastUndoInfo = (threadId: thread.id, folderId: folderId)
            }
        } catch {
            withAnimation { errorToastMessage = "Failed to archive thread" }
        }
    }

    private func deleteThread(_ thread: VaultMailFeature.Thread) async {
        do {
            let folderId = selectedFolder?.id ?? ""
            try await manageThreadActions.deleteThread(id: thread.id)
            threads.removeAll { $0.id == thread.id }
            if threads.isEmpty {
                viewState = selectedCategory != nil ? .emptyFiltered : .empty
            }
            await notificationCoordinator.didRemoveThread(threadId: thread.id)
            withAnimation {
                actionToastMessage = "Thread deleted"
                actionToastUndoInfo = (threadId: thread.id, folderId: folderId)
            }
        } catch {
            withAnimation { errorToastMessage = "Failed to delete thread" }
        }
    }

    /// Undo the last archive/delete action by moving the thread back to its original folder.
    private func undoLastAction() {
        guard let info = actionToastUndoInfo else { return }
        let threadId = info.threadId
        let folderId = info.folderId
        withAnimation {
            actionToastMessage = nil
            actionToastUndoInfo = nil
        }
        Task {
            do {
                try await manageThreadActions.moveThread(id: threadId, toFolderId: folderId)
                await reloadThreads()
            } catch {
                withAnimation { errorToastMessage = "Failed to undo action" }
            }
        }
    }

    /// Toggle read/unread status for a thread via swipe action.
    private func toggleReadStatus(_ thread: Thread) async {
        do {
            try await manageThreadActions.toggleReadStatus(threadId: thread.id)
            await reloadThreads()
        } catch {
            withAnimation { errorToastMessage = "Failed to update read status" }
        }
    }

    /// Toggle star/unstar status for a thread via swipe action.
    private func toggleStarStatus(_ thread: Thread) async {
        do {
            try await manageThreadActions.toggleStarStatus(threadId: thread.id)
            await reloadThreads()
        } catch {
            withAnimation { errorToastMessage = "Failed to update star" }
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
            withAnimation { errorToastMessage = "Failed to archive \(ids.count) threads" }
        }
    }

    private func batchDelete() async {
        let ids = Array(selectedThreadIds)
        do {
            try await manageThreadActions.deleteThreads(ids: ids)
            threads.removeAll { ids.contains($0.id) }
            exitMultiSelectMode()
        } catch {
            withAnimation { errorToastMessage = "Failed to delete \(ids.count) threads" }
        }
    }

    private func batchMarkRead() async {
        let ids = Array(selectedThreadIds)
        do {
            try await manageThreadActions.markThreadsRead(ids: ids)
            exitMultiSelectMode()
            await reloadThreads()
        } catch {
            withAnimation { errorToastMessage = "Failed to mark threads as read" }
        }
    }

    private func batchMarkUnread() async {
        let ids = Array(selectedThreadIds)
        do {
            try await manageThreadActions.markThreadsUnread(ids: ids)
            exitMultiSelectMode()
            await reloadThreads()
        } catch {
            withAnimation { errorToastMessage = "Failed to mark threads as unread" }
        }
    }

    private func batchStar() async {
        let ids = Array(selectedThreadIds)
        do {
            try await manageThreadActions.starThreads(ids: ids)
            exitMultiSelectMode()
            await reloadThreads()
        } catch {
            withAnimation { errorToastMessage = "Failed to star threads" }
        }
    }

    private func batchMove(toFolderId: String) async {
        let ids = Array(selectedThreadIds)
        do {
            try await manageThreadActions.moveThreads(ids: ids, toFolderId: toFolderId)
            threads.removeAll { ids.contains($0.id) }
            exitMultiSelectMode()
        } catch {
            withAnimation { errorToastMessage = "Failed to move threads" }
        }
    }

    private func exitMultiSelectMode() {
        isMultiSelectMode = false
        selectedThreadIds.removeAll()
        if threads.isEmpty {
            viewState = selectedCategory != nil ? .emptyFiltered : .empty
        }
    }

    // MARK: - Composer Dismiss Handling

    private func handleComposerDismiss(_ result: ComposerDismissResult) {
        switch result {
        case .sent(let emailId):
            let delay = settings.undoSendDelay.rawValue
            undoSendManager.startCountdown(emailId: emailId, delaySeconds: delay) { emailId in
                // Timer expired — execute the actual send
                do {
                    try await composeEmail.executeSend(emailId: emailId)
                    NSLog("[UI] executeSend completed successfully for \(emailId)")
                } catch {
                    NSLog("[UI] executeSend FAILED for \(emailId): \(error)")
                }
                // Clean up temp attachment files now that send completed (or failed)
                AttachmentPickerView.cleanupTempAttachments()
            }
        case .savedDraft:
            // Could show a "Draft saved" toast here
            break
        case .discarded, .cancelled:
            break
        }
    }

    // MARK: - AI Classification

    /// Enqueue newly synced emails for AI processing.
    ///
    /// Accepts the complete list of newly synced emails from the sync use case,
    /// ensuring ALL synced emails are processed — not just the currently loaded
    /// thread page. The queue itself filters to uncategorized-only.
    /// Sorted oldest→newest so the most recent email is processed last,
    /// ensuring Thread.aiCategory reflects the latest email's category.
    ///
    /// Spec ref: FR-AI-07, AC-A-04b
    private func runAIClassification(for syncedEmails: [Email]) {
        guard let queue = aiProcessingQueue else { return }
        let sorted = syncedEmails
            .sorted { ($0.dateReceived ?? .distantPast) < ($1.dateReceived ?? .distantPast) }
        guard !sorted.isEmpty else { return }
        NSLog("[AI] Enqueuing \(sorted.count) synced emails for AI classification")
        queue.enqueue(emails: sorted)
    }

    // MARK: - Inline Search (FR-SEARCH-01..03)

    /// Execute hybrid search with the current query and filters.
    private func performSearch() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)

        // Return to idle when query and filters are empty
        if trimmed.isEmpty && !searchFilters.hasActiveFilters {
            searchViewState = .idle
            searchResults = []
            return
        }

        searchViewState = .searching

        guard let searchUseCase else {
            searchViewState = .empty
            return
        }

        // Build scope from current selection
        let scope: SearchScope
        if isCurrentFolderScope, let folderId = selectedFolder?.id {
            scope = .currentFolder(folderId: folderId)
        } else {
            scope = .allMail
        }

        // Parse natural language query
        var query = SearchQueryParser.parse(trimmed, scope: scope)
        // Merge manual filter chips with NL-parsed filters
        query.filters = mergeSearchFilters(parsed: query.filters, manual: searchFilters)

        // Resolve AI engine for semantic search (nil-safe graceful degradation)
        let engine: (any AIEngineProtocol)?
        if let resolver = aiEngineResolver {
            engine = await resolver.resolveGenerativeEngine()
        } else {
            engine = nil
        }

        // Execute hybrid search
        let results = await searchUseCase.execute(query: query, engine: engine)

        guard !Task.isCancelled else { return }

        searchResults = results

        // Deduplicate thread IDs preserving first (highest-scored) occurrence (P2 fix)
        var seenThreadIds = Set<String>()
        var uniqueThreadIds: [String] = []
        for result in results {
            if seenThreadIds.insert(result.threadId).inserted {
                uniqueThreadIds.append(result.threadId)
            }
        }

        // Fetch full Thread objects from SwiftData for unified ThreadRowView display
        let fetchedThreads = fetchThreadsForSearch(ids: uniqueThreadIds)
        // Preserve search ranking order
        let threadMap = Dictionary(uniqueKeysWithValues: fetchedThreads.map { ($0.id, $0) })
        searchThreads = uniqueThreadIds.compactMap { threadMap[$0] }

        searchViewState = searchThreads.isEmpty ? .empty : .results

        // Save to recent searches
        if !trimmed.isEmpty {
            saveRecentSearch(trimmed)
        }
    }

    /// Fetch Thread objects from SwiftData matching the given IDs.
    private func fetchThreadsForSearch(ids: [String]) -> [VaultMailFeature.Thread] {
        guard !ids.isEmpty else { return [] }
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<VaultMailFeature.Thread>(
            predicate: #Predicate<VaultMailFeature.Thread> { thread in
                idSet.contains(thread.id)
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Merges manually-applied filter chips with filters extracted from NL parsing.
    /// Manual filters take priority over parsed ones.
    private func mergeSearchFilters(parsed: SearchFilters, manual: SearchFilters) -> SearchFilters {
        SearchFilters(
            sender: manual.sender ?? parsed.sender,
            dateRange: manual.dateRange ?? parsed.dateRange,
            hasAttachment: manual.hasAttachment ?? parsed.hasAttachment,
            folder: manual.folder ?? parsed.folder,
            category: manual.category ?? parsed.category,
            isRead: manual.isRead ?? parsed.isRead
        )
    }

    // MARK: - Recent Searches Persistence

    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
    }

    private func saveRecentSearch(_ query: String) {
        var searches = recentSearches
        searches.removeAll { $0 == query }
        searches.insert(query, at: 0)
        if searches.count > maxRecentSearches {
            searches = Array(searches.prefix(maxRecentSearches))
        }
        recentSearches = searches
        UserDefaults.standard.set(searches, forKey: recentSearchesKey)
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

// MARK: - Search Debounce Trigger

/// Equatable trigger for .task(id:) — changes to text or filters cancel the
/// previous task and start a new debounced search.
private struct SearchDebounceTrigger: Equatable {
    let text: String
    let filters: SearchFilters
    let isCurrentFolderScope: Bool
}
