#if os(macOS)
import SwiftUI
import SwiftData

/// Root macOS view using NavigationSplitView for a native three-pane layout.
///
/// Replaces the iOS NavigationStack + BottomTabBar pattern on macOS.
/// Column layout: Sidebar (accounts/folders) | Content (thread list) | Detail (email).
///
/// Spec ref: FR-MAC-01 (Three-Pane Layout), FR-MAC-10 (Window Configuration)
@MainActor
public struct MacOSMainView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext

    // MARK: - Use Cases (injected from ContentView)

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

    public init(
        fetchThreads: FetchThreadsUseCaseProtocol,
        manageThreadActions: ManageThreadActionsUseCaseProtocol,
        manageAccounts: ManageAccountsUseCaseProtocol,
        syncEmails: SyncEmailsUseCaseProtocol,
        fetchEmailDetail: FetchEmailDetailUseCaseProtocol,
        markRead: MarkReadUseCaseProtocol,
        downloadAttachment: DownloadAttachmentUseCaseProtocol,
        composeEmail: ComposeEmailUseCaseProtocol,
        queryContacts: QueryContactsUseCaseProtocol,
        idleMonitor: IDLEMonitorUseCaseProtocol? = nil,
        modelManager: ModelManager = ModelManager(),
        aiEngineResolver: AIEngineResolver? = nil,
        aiProcessingQueue: AIProcessingQueue? = nil,
        summarizeThread: SummarizeThreadUseCaseProtocol? = nil,
        smartReply: SmartReplyUseCaseProtocol? = nil,
        searchUseCase: SearchEmailsUseCase? = nil
    ) {
        self.fetchThreads = fetchThreads
        self.manageThreadActions = manageThreadActions
        self.manageAccounts = manageAccounts
        self.syncEmails = syncEmails
        self.fetchEmailDetail = fetchEmailDetail
        self.markRead = markRead
        self.downloadAttachment = downloadAttachment
        self.composeEmail = composeEmail
        self.queryContacts = queryContacts
        self.idleMonitor = idleMonitor
        self.modelManager = modelManager
        self.aiEngineResolver = aiEngineResolver
        self.aiProcessingQueue = aiProcessingQueue
        self.summarizeThread = summarizeThread
        self.smartReply = smartReply
        self.searchUseCase = searchUseCase
    }

    // MARK: - Navigation State

    /// Column visibility state for the split view.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// Currently selected account (nil = Unified Inbox).
    @State private var selectedAccount: Account? = nil

    /// Currently selected folder.
    @State private var selectedFolder: Folder? = nil

    /// Currently selected thread ID — drives detail column content.
    @State private var selectedThreadID: String? = nil

    /// Multi-selection for ⌘-click / ⇧-click support.
    @State private var selectedThreadIDs: Set<String> = []

    // MARK: - Data State

    @State private var accounts: [Account] = []
    @State private var folders: [Folder] = []
    /// All folders across every account — used by the sidebar to show
    /// every account's folder tree simultaneously.
    @State private var allFolders: [Folder] = []
    @State private var threads: [VaultMailFeature.Thread] = []
    @State private var hasLoaded = false

    // Category filtering
    @State private var selectedCategory: String? = nil
    @State private var unreadCounts: [String?: Int] = [:]
    @State private var categoryPerFolder: [String: String?] = [:]

    // Pagination
    @State private var paginationCursor: Date? = nil
    @State private var hasMorePages = false
    @State private var isLoadingMore = false

    // Sync
    @State private var isSyncing = false
    @State private var syncTask: Task<Void, Never>?
    @State private var idleTask: Task<Void, Never>?

    // Search
    @State private var searchText = ""
    @State private var isSearchActive = false

    // Compose sheet
    @State private var composerMode: ComposerMode? = nil

    // Error
    @State private var errorMessage: String? = nil

    // Outbox
    @State private var outboxEmails: [Email] = []

    // Undo send
    @State private var undoSendManager = UndoSendManager()

    // Menu bar command state (FR-MAC-07)
    @State private var commandState = MacCommandState()

    // MARK: - View State Enum

    enum ViewState: Equatable {
        case loading, loaded, empty, emptyFiltered, error(String), offline

        static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.loaded, .loaded), (.empty, .empty),
                 (.emptyFiltered, .emptyFiltered), (.offline, .offline):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    @State private var viewState: ViewState = .loading

    // MARK: - Derived

    private var isOutboxSelected: Bool {
        guard let folder = selectedFolder else { return false }
        return FolderType(rawValue: folder.folderType) == nil && folder.name == "Outbox"
    }

    private var showCategoryTabs: Bool {
        guard !isOutboxSelected else { return false }
        let hasVisible = settings.categoryTabVisibility.values.contains(true)
        let uncategorizedRaw = AICategory.uncategorized.rawValue
        let hasAI = threads.contains {
            guard let cat = $0.aiCategory else { return false }
            return cat != uncategorizedRaw
        }
        return hasVisible && hasAI
    }

    private var navigationTitle: String {
        if selectedAccount == nil {
            return "All Inboxes"
        }
        return selectedFolder?.name ?? "Inbox"
    }

    private func accountColor(for thread: VaultMailFeature.Thread) -> Color? {
        guard selectedAccount == nil, accounts.count > 1 else { return nil }
        return AvatarView.color(for: thread.accountId)
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // SIDEBAR
            SidebarView(
                accounts: accounts,
                folders: allFolders,
                selectedAccount: $selectedAccount,
                selectedFolder: $selectedFolder,
                unreadCounts: unreadCounts,
                outboxCount: outboxEmails.count,
                onSelectUnifiedInbox: {
                    selectedAccount = nil
                    selectedFolder = nil
                    selectedCategory = nil
                    selectedThreadID = nil
                    selectedThreadIDs.removeAll()
                    Task { await reloadThreads() }
                },
                onSelectAccount: { account in
                    selectedAccount = account
                    selectedCategory = nil
                    selectedThreadID = nil
                    selectedThreadIDs.removeAll()
                    Task { await switchToAccount(account) }
                },
                onSelectFolder: { folder in
                    selectFolder(folder)
                },
                onAddAccount: {
                    Task { await addAccountFromSidebar() }
                },
                onRemoveAccount: { account in
                    Task { await removeAccountFromSidebar(account) }
                }
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            // CONTENT — Thread List
            MacThreadListContentView(
                viewState: viewState,
                threads: threads,
                selectedThreadID: $selectedThreadID,
                selectedThreadIDs: $selectedThreadIDs,
                selectedCategory: $selectedCategory,
                unreadCounts: unreadCounts,
                showCategoryTabs: showCategoryTabs,
                isOutboxSelected: isOutboxSelected,
                outboxEmails: outboxEmails,
                hasMorePages: hasMorePages,
                isLoadingMore: isLoadingMore,
                isSyncing: isSyncing,
                errorMessage: errorMessage,
                accountColorProvider: accountColor,
                onLoadMore: { Task { await loadMoreThreads() } },
                onArchive: { thread in Task { await archiveThread(thread) } },
                onDelete: { thread in Task { await deleteThread(thread) } },
                onToggleRead: { thread in Task { await toggleRead(thread) } },
                onToggleStar: { thread in Task { await toggleStar(thread) } },
                onMoveToFolder: { thread in /* show move sheet */ },
                onReply: { threadId in
                    let accountId = selectedAccount?.id ?? accounts.first?.id ?? ""
                    composerMode = .reply(email: ComposerEmailContext(
                        emailId: threadId, accountId: accountId, threadId: threadId,
                        messageId: "", fromAddress: "", subject: ""
                    ))
                },
                onReplyAll: { threadId in
                    let accountId = selectedAccount?.id ?? accounts.first?.id ?? ""
                    composerMode = .replyAll(email: ComposerEmailContext(
                        emailId: threadId, accountId: accountId, threadId: threadId,
                        messageId: "", fromAddress: "", subject: ""
                    ))
                },
                onForward: { threadId in
                    let accountId = selectedAccount?.id ?? accounts.first?.id ?? ""
                    composerMode = .forward(email: ComposerEmailContext(
                        emailId: threadId, accountId: accountId, threadId: threadId,
                        messageId: "", fromAddress: "", subject: ""
                    ))
                }
            )
            .navigationTitle(navigationTitle)
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            // DETAIL — Email Detail or Placeholder
            if let threadId = selectedThreadID {
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
            } else if selectedThreadIDs.count > 1 {
                multiSelectPlaceholder
            } else {
                noSelectionPlaceholder
            }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search emails")
        .toolbar { macToolbarContent }
        .focusedValue(\.macCommandState, commandState)
        .environment(undoSendManager)
        .sheet(item: $composerMode) { mode in
            composerSheet(for: mode)
        }
        .task {
            await initialLoad()
        }
        .onChange(of: selectedCategory) {
            Task { await reloadThreads() }
        }
        .onChange(of: selectedThreadID) {
            updateCommandState()
        }
        .onDisappear {
            idleTask?.cancel()
            syncTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.accountsDidChangeNotification)) { _ in
            Task { await refreshAfterAccountChange() }
        }
        .preferredColorScheme(settings.colorScheme)
    }

    // MARK: - Placeholders

    private var noSelectionPlaceholder: some View {
        ContentUnavailableView(
            "No Conversation Selected",
            systemImage: "envelope",
            description: Text("Select a conversation from the list to read it here.")
        )
    }

    private var multiSelectPlaceholder: some View {
        ContentUnavailableView(
            "\(selectedThreadIDs.count) Conversations Selected",
            systemImage: "checkmark.circle",
            description: Text("Use the toolbar to perform actions on selected conversations.")
        )
    }

    // MARK: - macOS Toolbar (FR-MAC-03)

    @ToolbarContentBuilder
    private var macToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Button {
                composerMode = .new(accountId: selectedAccount?.id ?? accounts.first?.id ?? "")
            } label: {
                Label("Compose", systemImage: "square.and.pencil")
            }
            .accessibilityLabel("New Email")

            Spacer()

            // Thread action buttons (enabled when a thread is selected)
            Group {
                Button {
                    archiveSelectedThread()
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .disabled(selectedThreadID == nil)
                .accessibilityLabel("Archive")

                Button {
                    deleteSelectedThread()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedThreadID == nil)
                .accessibilityLabel("Delete")

                Button {
                    toggleReadSelectedThread()
                } label: {
                    Label("Read/Unread", systemImage: "envelope")
                }
                .disabled(selectedThreadID == nil)
                .accessibilityLabel("Toggle Read Status")

                Button {
                    toggleStarSelectedThread()
                } label: {
                    Label("Star", systemImage: "star")
                }
                .disabled(selectedThreadID == nil)
                .accessibilityLabel("Toggle Star")
            }

            Spacer()

            Button {
                syncTask?.cancel()
                syncTask = Task {
                    isSyncing = true
                    defer { isSyncing = false; syncTask = nil }
                    guard let accountId = selectedAccount?.id else { return }
                    _ = try? await syncEmails.syncAccountInboxFirst(accountId: accountId, onInboxSynced: { _ in
                        await loadThreadsAndCounts()
                    })
                    await loadThreadsAndCounts()
                }
            } label: {
                Label("Sync", systemImage: "arrow.clockwise")
            }
            .disabled(isSyncing)
            .accessibilityLabel("Refresh")
        }
    }

    // MARK: - Toolbar Thread Actions

    private func archiveSelectedThread() {
        guard let threadId = selectedThreadID,
              let thread = threads.first(where: { $0.id == threadId }) else { return }
        Task { await archiveThread(thread) }
    }

    private func deleteSelectedThread() {
        guard let threadId = selectedThreadID,
              let thread = threads.first(where: { $0.id == threadId }) else { return }
        Task { await deleteThread(thread) }
    }

    private func toggleReadSelectedThread() {
        guard let threadId = selectedThreadID,
              let thread = threads.first(where: { $0.id == threadId }) else { return }
        Task { await toggleRead(thread) }
    }

    private func toggleStarSelectedThread() {
        guard let threadId = selectedThreadID,
              let thread = threads.first(where: { $0.id == threadId }) else { return }
        Task { await toggleStar(thread) }
    }

    // MARK: - Command State Update (FR-MAC-07)

    private func updateCommandState() {
        commandState.hasSelection = selectedThreadID != nil

        commandState.onCompose = { [accounts, selectedAccount] in
            composerMode = .new(accountId: selectedAccount?.id ?? accounts.first?.id ?? "")
        }

        commandState.onReply = { [selectedThreadID, selectedAccount, accounts] in
            guard let threadId = selectedThreadID else { return }
            let accountId = selectedAccount?.id ?? accounts.first?.id ?? ""
            composerMode = .reply(email: ComposerEmailContext(
                emailId: threadId, accountId: accountId, threadId: threadId,
                messageId: "", fromAddress: "", subject: ""
            ))
        }

        commandState.onReplyAll = { [selectedThreadID, selectedAccount, accounts] in
            guard let threadId = selectedThreadID else { return }
            let accountId = selectedAccount?.id ?? accounts.first?.id ?? ""
            composerMode = .replyAll(email: ComposerEmailContext(
                emailId: threadId, accountId: accountId, threadId: threadId,
                messageId: "", fromAddress: "", subject: ""
            ))
        }

        commandState.onForward = { [selectedThreadID, selectedAccount, accounts] in
            guard let threadId = selectedThreadID else { return }
            let accountId = selectedAccount?.id ?? accounts.first?.id ?? ""
            composerMode = .forward(email: ComposerEmailContext(
                emailId: threadId, accountId: accountId, threadId: threadId,
                messageId: "", fromAddress: "", subject: ""
            ))
        }

        commandState.onArchive = {
            archiveSelectedThread()
        }

        commandState.onDelete = {
            deleteSelectedThread()
        }

        commandState.onToggleRead = {
            toggleReadSelectedThread()
        }

        commandState.onToggleStar = {
            toggleStarSelectedThread()
        }

        commandState.onMove = {
            // TODO: Show move-to-folder sheet
        }

        commandState.onSync = {
            syncTask?.cancel()
            syncTask = Task {
                isSyncing = true
                defer { isSyncing = false; syncTask = nil }
                guard let accountId = selectedAccount?.id else { return }
                _ = try? await syncEmails.syncAccountInboxFirst(accountId: accountId, onInboxSynced: { _ in
                    await loadThreadsAndCounts()
                })
                await loadThreadsAndCounts()
            }
        }
    }

    // MARK: - Composer Sheet

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
        .frame(minWidth: 500, minHeight: 400)
    }

    // MARK: - Data Loading

    private func initialLoad() async {
        viewState = .loading
        do {
            accounts = try await manageAccounts.getAccounts()
            guard let firstAccount = accounts.first else {
                viewState = .empty
                hasLoaded = true
                return
            }

            // Load folders for ALL accounts so the sidebar shows every folder tree
            var combined: [Folder] = []
            for account in accounts {
                let accountFolders = try await fetchThreads.fetchFolders(accountId: account.id)
                combined.append(contentsOf: accountFolders)
            }
            allFolders = combined

            selectedAccount = firstAccount
            folders = combined.filter { $0.account?.id == firstAccount.id }
            let inboxType = FolderType.inbox.rawValue
            selectedFolder = folders.first(where: { $0.folderType == inboxType }) ?? folders.first
            await loadThreadsAndCounts()

            // Background sync — sync ALL accounts, starting with the selected one
            isSyncing = true
            let allAccountIDs = accounts.map(\.id)
            let selectedId = firstAccount.id
            syncTask = Task {
                defer { isSyncing = false; syncTask = nil }

                // Sync selected account first so user sees results immediately
                await syncSingleAccount(selectedId, isSelected: true)

                // Sync remaining accounts in background
                for accountId in allAccountIDs where accountId != selectedId {
                    guard !Task.isCancelled else { return }
                    await syncSingleAccount(accountId, isSelected: false)
                }

                startIDLEMonitor()
            }
            hasLoaded = true
        } catch {
            viewState = .error(error.localizedDescription)
            hasLoaded = true
        }
    }

    /// Syncs a single account's IMAP folders and emails, updating the sidebar.
    /// - Parameters:
    ///   - accountId: The account to sync.
    ///   - isSelected: If true, also updates `folders` and `selectedFolder` for the detail pane.
    private func syncSingleAccount(_ accountId: String, isSelected: Bool) async {
        do {
            _ = try await syncEmails.syncAccountInboxFirst(
                accountId: accountId,
                onInboxSynced: { _ in
                    if let fresh = try? await fetchThreads.fetchFolders(accountId: accountId) {
                        allFolders = allFolders.filter { $0.account?.id != accountId } + fresh
                        if isSelected {
                            folders = fresh
                            let inboxType = FolderType.inbox.rawValue
                            selectedFolder = fresh.first(where: { $0.folderType == inboxType }) ?? fresh.first
                        }
                    }
                    if isSelected {
                        await loadThreadsAndCounts()
                    }
                }
            )
            guard !Task.isCancelled else { return }
            let freshFolders = try await fetchThreads.fetchFolders(accountId: accountId)
            allFolders = allFolders.filter { $0.account?.id != accountId } + freshFolders
            if isSelected {
                folders = freshFolders
                if let currentType = selectedFolder?.folderType {
                    selectedFolder = freshFolders.first(where: { $0.folderType == currentType }) ?? freshFolders.first
                }
                await loadThreadsAndCounts()
            }
        } catch is CancellationError {
            // cancelled
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Sync failed for account: \(error.localizedDescription)"
        }
    }

    /// Refreshes the account list and reloads data after accounts are added
    /// or removed from the Settings window (cross-window notification).
    private func refreshAfterAccountChange() async {
        do {
            // Capture old account IDs BEFORE updating state, so we can
            // detect which accounts are newly added.
            let oldAccountIDs = Set(accounts.map(\.id))

            let freshAccounts = try await manageAccounts.getAccounts()
            accounts = freshAccounts

            if freshAccounts.isEmpty {
                viewState = .empty
                folders = []
                allFolders = []
                threads = []
                selectedAccount = nil
                selectedFolder = nil
                return
            }

            // If the previously selected account was removed, select the first
            if let current = selectedAccount,
               !freshAccounts.contains(where: { $0.id == current.id }) {
                selectedAccount = freshAccounts.first
            }

            // If no account was selected (first add), do full initial load
            if selectedAccount == nil {
                await initialLoad()
                return
            }

            // Reload folders for all accounts from local DB
            var combined: [Folder] = []
            for account in freshAccounts {
                let accountFolders = try await fetchThreads.fetchFolders(accountId: account.id)
                combined.append(contentsOf: accountFolders)
            }
            allFolders = combined

            if let sel = selectedAccount {
                folders = combined.filter { $0.account?.id == sel.id }
                if selectedFolder == nil {
                    let inboxType = FolderType.inbox.rawValue
                    selectedFolder = folders.first(where: { $0.folderType == inboxType }) ?? folders.first
                }
            }
            await loadThreadsAndCounts()

            // Identify newly added accounts and sync them
            let newAccountIDs = freshAccounts
                .filter { !oldAccountIDs.contains($0.id) }
                .map(\.id)

            if !newAccountIDs.isEmpty {
                isSyncing = true
                syncTask?.cancel()
                syncTask = Task {
                    defer { isSyncing = false; syncTask = nil }
                    for accountId in newAccountIDs {
                        guard !Task.isCancelled else { return }
                        let isSelected = selectedAccount?.id == accountId
                        await syncSingleAccount(accountId, isSelected: isSelected)
                    }
                }
            }
        } catch {
            errorMessage = "Failed to refresh accounts: \(error.localizedDescription)"
        }
    }

    private func reloadThreads() async {
        viewState = .loading
        threads = []
        paginationCursor = nil
        hasMorePages = false
        selectedThreadID = nil
        selectedThreadIDs.removeAll()
        await loadThreadsAndCounts()
    }

    private func loadThreadsAndCounts() async {
        do {
            let page: ThreadPage
            let counts: [String?: Int]

            if let account = selectedAccount, let folder = selectedFolder {
                page = try await fetchThreads.fetchThreads(
                    accountId: account.id, folderId: folder.id,
                    category: selectedCategory, cursor: nil,
                    pageSize: AppConstants.threadListPageSize
                )
                counts = try await fetchThreads.fetchUnreadCounts(accountId: account.id, folderId: folder.id)
            } else {
                page = try await fetchThreads.fetchUnifiedThreads(
                    category: selectedCategory, cursor: nil,
                    pageSize: AppConstants.threadListPageSize
                )
                counts = try await fetchThreads.fetchUnreadCountsUnified()
            }

            threads = page.threads
            paginationCursor = page.nextCursor
            hasMorePages = page.hasMore
            unreadCounts = counts
            viewState = threads.isEmpty ? (selectedCategory != nil ? .emptyFiltered : .empty) : .loaded
        } catch {
            if !threads.isEmpty {
                errorMessage = error.localizedDescription
                viewState = .loaded
            } else {
                viewState = .error(error.localizedDescription)
            }
        }
    }

    private func loadMoreThreads() async {
        guard hasMorePages, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page: ThreadPage
            if let account = selectedAccount, let folder = selectedFolder {
                page = try await fetchThreads.fetchThreads(
                    accountId: account.id, folderId: folder.id,
                    category: selectedCategory, cursor: paginationCursor,
                    pageSize: AppConstants.threadListPageSize
                )
            } else {
                page = try await fetchThreads.fetchUnifiedThreads(
                    category: selectedCategory, cursor: paginationCursor,
                    pageSize: AppConstants.threadListPageSize
                )
            }
            threads.append(contentsOf: page.threads)
            paginationCursor = page.nextCursor
            hasMorePages = page.hasMore
        } catch {
            // Silently fail pagination on macOS — user can scroll again to retry
        }
    }

    private func switchToAccount(_ account: Account) async {
        do {
            let freshFolders = try await fetchThreads.fetchFolders(accountId: account.id)
            folders = freshFolders
            allFolders = allFolders.filter { $0.account?.id != account.id } + freshFolders
            let inboxType = FolderType.inbox.rawValue
            selectedFolder = folders.first(where: { $0.folderType == inboxType }) ?? folders.first
            await reloadThreads()
        } catch {
            viewState = .error(error.localizedDescription)
        }
    }

    private func selectFolder(_ folder: Folder) {
        if let currentFolder = selectedFolder {
            categoryPerFolder[currentFolder.id] = selectedCategory
        }
        selectedFolder = folder
        selectedThreadID = nil
        selectedThreadIDs.removeAll()

        if let saved = categoryPerFolder[folder.id] {
            selectedCategory = saved
        } else {
            selectedCategory = nil
        }

        if isOutboxSelected {
            Task { await loadOutboxEmails() }
        } else {
            Task { await reloadThreads() }
        }
    }

    private func loadOutboxEmails() async {
        do {
            outboxEmails = try await fetchThreads.fetchOutboxEmails(accountId: selectedAccount?.id)
            viewState = outboxEmails.isEmpty ? .empty : .loaded
        } catch {
            viewState = .error(error.localizedDescription)
        }
    }

    // MARK: - Thread Actions

    private func archiveThread(_ thread: VaultMailFeature.Thread) async {
        do {
            try await manageThreadActions.archiveThread(id: thread.id)
            threads.removeAll { $0.id == thread.id }
            if selectedThreadID == thread.id { advanceSelection(after: thread.id) }
            if threads.isEmpty { viewState = selectedCategory != nil ? .emptyFiltered : .empty }
        } catch {
            errorMessage = "Couldn't archive. Click to retry."
        }
    }

    private func deleteThread(_ thread: VaultMailFeature.Thread) async {
        do {
            try await manageThreadActions.deleteThread(id: thread.id)
            threads.removeAll { $0.id == thread.id }
            if selectedThreadID == thread.id { advanceSelection(after: thread.id) }
            if threads.isEmpty { viewState = selectedCategory != nil ? .emptyFiltered : .empty }
        } catch {
            errorMessage = "Couldn't delete. Click to retry."
        }
    }

    private func toggleRead(_ thread: VaultMailFeature.Thread) async {
        do {
            try await manageThreadActions.toggleReadStatus(threadId: thread.id)
            await loadThreadsAndCounts()
        } catch {
            errorMessage = "Couldn't update read status."
        }
    }

    private func toggleStar(_ thread: VaultMailFeature.Thread) async {
        do {
            try await manageThreadActions.toggleStarStatus(threadId: thread.id)
            await loadThreadsAndCounts()
        } catch {
            errorMessage = "Couldn't update star."
        }
    }

    /// After delete/archive, select the next thread in the list.
    private func advanceSelection(after threadId: String) {
        guard let idx = threads.firstIndex(where: { $0.id == threadId }) else {
            selectedThreadID = threads.first?.id
            return
        }
        if idx < threads.count {
            selectedThreadID = threads[idx].id
        } else if let last = threads.last {
            selectedThreadID = last.id
        } else {
            selectedThreadID = nil
        }
    }

    // MARK: - IDLE Monitor

    private func startIDLEMonitor() {
        idleTask?.cancel()
        guard let monitor = idleMonitor,
              let accountId = selectedAccount?.id,
              let folderPath = selectedFolder?.imapPath else { return }

        idleTask = Task {
            var retryDelay: Duration = .seconds(2)
            while !Task.isCancelled {
                let stream = monitor.monitor(accountId: accountId, folderImapPath: folderPath)
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    if case .newMail = event {
                        if let folderId = selectedFolder?.id {
                            _ = try? await syncEmails.syncFolder(accountId: accountId, folderId: folderId)
                            await loadThreadsAndCounts()
                        }
                        retryDelay = .seconds(2)
                    }
                }
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: retryDelay)
                retryDelay = min(retryDelay * 2, .seconds(60))
            }
        }
    }

    // MARK: - Sidebar Account Actions

    /// Adds a new account via OAuth directly from the sidebar.
    /// Reuses the same logic as MacSettingsView's addAccount.
    private func addAccountFromSidebar() async {
        do {
            let newAccount = try await manageAccounts.addAccountViaOAuth()
            let freshAccounts = try await manageAccounts.getAccounts()
            accounts = freshAccounts

            // Sync the newly added account's folders
            isSyncing = true
            syncTask?.cancel()
            syncTask = Task {
                defer { isSyncing = false; syncTask = nil }
                let isSelected = selectedAccount?.id == newAccount.id
                await syncSingleAccount(newAccount.id, isSelected: isSelected)
            }

            // Notify Settings window (if open) to refresh
            NotificationCenter.default.post(name: AppConstants.accountsDidChangeNotification, object: nil)
        } catch {
            // OAuth cancelled or failed — no action needed
        }
    }

    /// Removes an account from the sidebar. Called after user confirms in the alert.
    private func removeAccountFromSidebar(_ account: Account) async {
        do {
            let wasLast = try await manageAccounts.removeAccount(id: account.id)
            if wasLast {
                settings.isOnboardingComplete = false
            }

            let freshAccounts = try await manageAccounts.getAccounts()
            accounts = freshAccounts

            // Remove the account's folders from allFolders
            allFolders = allFolders.filter { $0.account?.id != account.id }

            if freshAccounts.isEmpty {
                viewState = .empty
                folders = []
                threads = []
                selectedAccount = nil
                selectedFolder = nil
                selectedThreadID = nil
                return
            }

            // If the removed account was selected, switch to the first remaining
            if selectedAccount?.id == account.id {
                selectedAccount = freshAccounts.first
                if let newAccount = selectedAccount {
                    await switchToAccount(newAccount)
                }
            }

            // Notify Settings window (if open) to refresh
            NotificationCenter.default.post(name: AppConstants.accountsDidChangeNotification, object: nil)
        } catch {
            errorMessage = "Failed to remove account: \(error.localizedDescription)"
        }
    }

    // MARK: - Composer Dismiss

    private func handleComposerDismiss(_ result: ComposerDismissResult) {
        switch result {
        case .sent(let emailId):
            let delay = settings.undoSendDelay.rawValue
            undoSendManager.startCountdown(emailId: emailId, delaySeconds: delay) { emailId in
                try? await composeEmail.executeSend(emailId: emailId)
            }
        case .savedDraft, .discarded, .cancelled:
            break
        }
    }
}
#endif
