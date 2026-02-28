#if os(macOS)
import SwiftUI
import SwiftData
import OSLog

/// Root macOS view using NavigationSplitView for a native three-pane layout.
///
/// Replaces the iOS NavigationStack + BottomTabBar pattern on macOS.
/// Column layout: Sidebar (accounts/folders) | Content (thread list) | Detail (email).
///
/// Spec ref: FR-MAC-01 (Three-Pane Layout), FR-MAC-10 (Window Configuration)
@MainActor
public struct MacOSMainView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(NotificationSyncCoordinator.self) private var notificationCoordinator

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
    var providerDiscovery: ProviderDiscovery?
    var connectionTestUseCase: ConnectionTestUseCaseProtocol?

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
        searchUseCase: SearchEmailsUseCase? = nil,
        providerDiscovery: ProviderDiscovery? = nil,
        connectionTestUseCase: ConnectionTestUseCaseProtocol? = nil
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
        self.providerDiscovery = providerDiscovery
        self.connectionTestUseCase = connectionTestUseCase
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
    @State private var paginationAnchorCursor: Date? = nil
    @State private var hasMorePages = false
    @State private var isLoadingMore = false
    @State private var reachedServerHistoryBoundary = false
    @State private var syncStatusText: String? = nil
    @State private var paginationError = false

    // Sync
    @State private var isSyncing = false
    @State private var syncTask: Task<Void, Never>?
    @State private var idleTasks: [String: Task<Void, Never>] = [:]

    // Search
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var searchThreads: [VaultMailFeature.Thread] = []
    @State private var isSearchLoading = false

    // Compose sheet
    @State private var composerMode: ComposerMode? = nil

    // Provider selection
    @State private var showProviderSelection = false

    // Error
    @State private var errorMessage: String? = nil

    // Outbox
    @State private var outboxEmails: [Email] = []

    // Undo send
    @State private var undoSendManager = UndoSendManager()

    // Menu bar command state (FR-MAC-07)
    @State private var commandState = MacCommandState()
    private let paginationLog = Logger(subsystem: "com.vaultmail.mac", category: "Pagination")

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

    private var displayThreads: [VaultMailFeature.Thread] {
        if isSearchActive {
            return searchThreads
        }
        return threads
    }

    private var isCatchUpEligibleContext: Bool {
        guard let folder = selectedFolder else { return false }
        guard selectedAccount != nil else { return false }
        guard !isOutboxSelected && !isSearchActive else { return false }
        return MacPaginationRuleEngine.isSyncableFolder(folderType: folder.folderType, imapPath: folder.imapPath)
    }

    private var shouldShowServerCatchUpSentinel: Bool {
        isCatchUpEligibleContext && !reachedServerHistoryBoundary
    }

    // MARK: - Body

    public var body: some View {
        applyThemeModifiers(
            to: applyInteractionModifiers(
                to: applyBaseModifiers(to: splitView)
            )
        )
    }

    private func applyBaseModifiers<Content: View>(to view: Content) -> some View {
        view
            .navigationSplitViewStyle(.balanced)
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search emails")
            .toolbar { macToolbarContent }
            .focusedValue(\.macCommandState, commandState)
            .environment(undoSendManager)
            .sheet(item: $composerMode) { mode in
                composerSheet(for: mode)
            }
            .sheet(isPresented: $showProviderSelection) {
                addAccountSheetContent
            }
            .task {
                await initialLoad()
            }
    }

    private func applyInteractionModifiers<Content: View>(to view: Content) -> some View {
        view
            .onChange(of: selectedCategory) {
                resetPaginationState()
                Task { await reloadThreads() }
            }
            .onChange(of: selectedAccount?.id) { _, _ in
                // Keep IDLE bound to the actively selected account.
                guard !isSyncing else { return }
                startIDLEMonitor()
            }
            .onChange(of: selectedFolder?.id) { _, _ in
                // Keep IDLE bound to the actively selected folder.
                guard !isSyncing else { return }
                startIDLEMonitor()
            }
            .onChange(of: searchText) { _, value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                isSearchActive = !trimmed.isEmpty
                if !trimmed.isEmpty {
                    resetPaginationState()
                }
                if trimmed.isEmpty {
                    searchThreads = []
                    isSearchLoading = false
                }
            }
            .onChange(of: selectedThreadID) {
                updateCommandState()
            }
            .onChange(of: notificationCoordinator.pendingThreadNavigation) { _, threadId in
                // Deep link: select thread when user taps a notification (NOTIF-17)
                if let threadId {
                    notificationCoordinator.pendingThreadNavigation = nil
                    selectedThreadID = threadId
                }
            }
            .onDisappear {
                stopIDLEMonitor()
                syncTask?.cancel()
            }
            .task(id: SearchDebounceTrigger(text: searchText, selectedFolderId: selectedFolder?.id, selectedAccountId: selectedAccount?.id)) {
                let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await performSearch()
            }
            .onReceive(NotificationCenter.default.publisher(for: AppConstants.accountsDidChangeNotification)) { _ in
                Task { await refreshAfterAccountChange() }
            }
    }

    private func applyThemeModifiers<Content: View>(to view: Content) -> some View {
        view
            .preferredColorScheme(settings.colorScheme)
            .tint(theme.colors.accent)
            .dynamicTypeSize(settings.fontSize.dynamicTypeSize)
            .onAppear {
                theme.colorScheme = colorScheme
                theme.fontScale = settings.fontSize.scale
            }
            .onChange(of: colorScheme) { _, newValue in
                theme.colorScheme = newValue
            }
            .onChange(of: settings.fontSize) { _, newValue in
                theme.fontScale = newValue.scale
            }
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } content: {
            threadListColumn
        } detail: {
            detailColumn
        }
    }

    private var sidebarColumn: some View {
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
                resetPaginationState()
                Task { await reloadThreads() }
            },
            onSelectAccount: { account in
                selectedAccount = account
                selectedCategory = nil
                selectedThreadID = nil
                selectedThreadIDs.removeAll()
                resetPaginationState()
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
        .navigationSplitViewColumnWidth(min: 150, ideal: 200)
    }

    private var threadListColumn: some View {
        MacThreadListContentView(
            viewState: viewState,
            threads: displayThreads,
            selectedThreadID: $selectedThreadID,
            selectedThreadIDs: $selectedThreadIDs,
            selectedCategory: $selectedCategory,
            unreadCounts: unreadCounts,
            showCategoryTabs: showCategoryTabs,
            isOutboxSelected: isOutboxSelected,
            outboxEmails: outboxEmails,
            hasMorePages: hasMorePages,
            shouldShowServerCatchUpSentinel: shouldShowServerCatchUpSentinel,
            isLoadingMore: isLoadingMore,
            syncStatusText: syncStatusText,
            paginationError: paginationError,
            isSyncing: isSyncing,
            errorMessage: errorMessage,
            searchQuery: searchText,
            isSearching: isSearchLoading,
            accountColorProvider: accountColor,
            onLoadMore: { Task { await loadMoreThreads() } },
            onArchive: { thread in Task { await archiveThread(thread) } },
            onDelete: { thread in Task { await deleteThread(thread) } },
            onToggleRead: { thread in Task { await toggleRead(thread) } },
            onToggleStar: { thread in Task { await toggleStar(thread) } },
            onMoveToFolder: { _ in /* show move sheet */ },
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
    }

    @ViewBuilder
    private var detailColumn: some View {
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

    @ViewBuilder
    private var addAccountSheetContent: some View {
        if let discovery = providerDiscovery, let connTest = connectionTestUseCase {
            MacAddAccountView(
                manageAccounts: manageAccounts,
                connectionTestUseCase: connTest,
                providerDiscovery: discovery,
                onAccountAdded: { newAccount in
                    showProviderSelection = false
                    Task {
                        accounts = (try? await manageAccounts.getAccounts()) ?? accounts
                        // Sync new account
                        isSyncing = true
                        syncTask?.cancel()
                        syncTask = Task {
                            defer { isSyncing = false; syncTask = nil }
                            await syncSingleAccount(newAccount.id, isSelected: selectedAccount?.id == newAccount.id)
                        }
                        NotificationCenter.default.post(name: AppConstants.accountsDidChangeNotification, object: nil)
                    }
                },
                onCancel: { showProviderSelection = false }
            )
        }
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
                syncTask = Task { await performManualSync() }
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
            syncTask = Task { await performManualSync() }
        }
    }

    private func performManualSync() async {
        isSyncing = true
        defer { isSyncing = false; syncTask = nil }

        do {
            var allSyncedEmails: [Email] = []
            if let accountId = selectedAccount?.id {
                let syncedEmails = try await syncEmails.syncAccountInboxFirst(
                    accountId: accountId,
                    onInboxSynced: { _ in
                        await loadThreadsAndCounts()
                    }
                )
                allSyncedEmails.append(contentsOf: syncedEmails)
            } else {
                for account in accounts where account.isActive {
                    let result = try await syncEmails.syncAccount(
                        accountId: account.id,
                        options: .full
                    )
                    allSyncedEmails.append(contentsOf: result.newEmails)
                }
            }

            runAIClassification(for: allSyncedEmails)
            await loadThreadsAndCounts()
            await notificationCoordinator.didSyncNewEmails(
                allSyncedEmails,
                fromBackground: false
            )
        } catch is CancellationError {
            // cancelled
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Sync failed: \(error.localizedDescription)"
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

            _ = await notificationCoordinator.requestAuthorization()

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
            let syncedEmails = try await syncEmails.syncAccountInboxFirst(
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
            runAIClassification(for: syncedEmails)
            // Mark first launch complete so subsequent syncs can deliver notifications.
            // The initial sync emails are suppressed to avoid flooding on first open.
            notificationCoordinator.markFirstLaunchComplete()
            // Notify notification coordinator about synced emails (NOTIF-03)
            await notificationCoordinator.didSyncNewEmails(
                syncedEmails,
                fromBackground: false
            )
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
        resetPaginationState()
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
                    category: selectedCategory, folderType: selectedFolder?.folderType,
                    cursor: nil, pageSize: AppConstants.threadListPageSize
                )
                counts = try await fetchThreads.fetchUnreadCountsUnified()
            }

            threads = uniqueByThreadId(page.threads)
            if !isSearchActive {
                searchThreads = []
            }
            paginationCursor = page.nextCursor
            paginationAnchorCursor = page.nextCursor ?? page.threads.compactMap(\.latestDate).min()
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
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        if !hasMorePages {
            await loadOlderFromServer()
            return
        }
        await appendNextLocalPage()
        // If local DB pagination just ended, continue with server catch-up
        // without waiting for a second sentinel appearance.
        if !hasMorePages {
            await loadOlderFromServer()
        }
    }

    private func loadOlderFromServer() async {
        guard MacPaginationRuleEngine.shouldAttemptCatchUp(
            hasMorePages: hasMorePages,
            isUnifiedMode: selectedAccount == nil,
            isSearchActive: isSearchActive,
            hasSelectedFolder: selectedFolder != nil,
            isOutboxSelected: isOutboxSelected,
            folderType: selectedFolder?.folderType,
            folderImapPath: selectedFolder?.imapPath
        ) else { return }
        guard let account = selectedAccount, let folder = selectedFolder else { return }

        syncStatusText = "Syncing older mail..."

        do {
            let result = try await syncEmails.syncFolder(
                accountId: account.id,
                folderId: folder.id,
                options: .catchUp
            )
            let anyNewEmails = !result.newEmails.isEmpty
            let anyPaused = folder.catchUpStatus == SyncCatchUpStatus.paused.rawValue

            guard anyNewEmails else {
                syncStatusText = anyPaused ? "Catch-up paused" : nil
                reachedServerHistoryBoundary = true
                return
            }

            reachedServerHistoryBoundary = false
            paginationError = false
            await appendNextLocalPage()
            syncStatusText = nil
        } catch {
            paginationError = true
            syncStatusText = nil
            paginationLog.error("catchUp failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func appendNextLocalPage() async {
        do {
            let page: ThreadPage
            let previousCursor = paginationCursor
            let oldestLoadedDate = threads.compactMap(\.latestDate).min()
            let effectiveCursor = paginationCursor ?? oldestLoadedDate ?? paginationAnchorCursor
            if paginationCursor == nil, !threads.isEmpty, oldestLoadedDate == nil, paginationAnchorCursor == nil {
                paginationError = true
                paginationLog.error("appendNextLocalPage aborted: no valid date cursor for non-empty thread list")
                return
            }
            if let account = selectedAccount, let folder = selectedFolder {
                page = try await fetchThreads.fetchThreads(
                    accountId: account.id,
                    folderId: folder.id,
                    category: selectedCategory,
                    cursor: effectiveCursor,
                    pageSize: AppConstants.threadListPageSize
                )
            } else {
                page = try await fetchThreads.fetchUnifiedThreads(
                    category: selectedCategory,
                    folderType: selectedFolder?.folderType,
                    cursor: effectiveCursor,
                    pageSize: AppConstants.threadListPageSize
                )
            }

            if !page.threads.isEmpty {
                var seen = Set(threads.map(\.id))
                let uniqueNewThreads = page.threads.filter { seen.insert($0.id).inserted }
                threads.append(contentsOf: uniqueNewThreads)
                // Safety: if backend returns duplicate-only rows with unchanged cursor,
                // don't stay in local-pagination spinner forever.
                if uniqueNewThreads.isEmpty && page.hasMore && page.nextCursor == previousCursor {
                    hasMorePages = false
                    paginationLog.warning(
                        "appendNextLocalPage duplicate-only page; forcing hasMorePages=false nextCursor=\(String(describing: page.nextCursor), privacy: .public)"
                    )
                }
            }
            if !isSearchActive {
                searchThreads = []
            }
            if let pageMinDate = page.threads.compactMap(\.latestDate).min() {
                if let anchor = paginationAnchorCursor {
                    paginationAnchorCursor = min(anchor, pageMinDate)
                } else {
                    paginationAnchorCursor = pageMinDate
                }
            }
            if let nextCursor = page.nextCursor {
                if let anchor = paginationAnchorCursor {
                    paginationAnchorCursor = min(anchor, nextCursor)
                } else {
                    paginationAnchorCursor = nextCursor
                }
            }
            paginationCursor = page.nextCursor
            hasMorePages = page.hasMore
            reachedServerHistoryBoundary = !page.hasMore && page.threads.isEmpty
            paginationError = false
        } catch {
            paginationError = true
            paginationLog.error("appendNextLocalPage failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func switchToAccount(_ account: Account) async {
        do {
            resetPaginationState()
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
        if folder.name != "Outbox", let folderAccount = folder.account {
            selectedAccount = folderAccount
        }
        resetPaginationState()
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

    private func resetPaginationState() {
        reachedServerHistoryBoundary = false
        syncStatusText = nil
        paginationError = false
        paginationAnchorCursor = nil
    }

    private func uniqueByThreadId(_ input: [VaultMailFeature.Thread]) -> [VaultMailFeature.Thread] {
        var seen = Set<String>()
        var output: [VaultMailFeature.Thread] = []
        output.reserveCapacity(input.count)
        for thread in input where seen.insert(thread.id).inserted {
            output.append(thread)
        }
        return output
    }

    // MARK: - Thread Actions

    private func archiveThread(_ thread: VaultMailFeature.Thread) async {
        do {
            try await manageThreadActions.archiveThread(id: thread.id)
            threads.removeAll { $0.id == thread.id }
            if selectedThreadID == thread.id { advanceSelection(after: thread.id) }
            if threads.isEmpty { viewState = selectedCategory != nil ? .emptyFiltered : .empty }
            await notificationCoordinator.didRemoveThread(threadId: thread.id)
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
            await notificationCoordinator.didRemoveThread(threadId: thread.id)
        } catch {
            errorMessage = "Couldn't delete. Click to retry."
        }
    }

    private func toggleRead(_ thread: VaultMailFeature.Thread) async {
        do {
            try await manageThreadActions.toggleReadStatus(threadId: thread.id)
            if thread.unreadCount > 0 {
                await notificationCoordinator.didMarkThreadRead(threadId: thread.id)
            }
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
        stopIDLEMonitor()
        guard let monitor = idleMonitor else { return }

        let monitoredAccounts = accounts.filter { $0.isActive }
        for account in monitoredAccounts {
            idleTasks[account.id] = Task {
                var retryDelay: Duration = .seconds(2)
                while !Task.isCancelled {
                    let inbox = allFolders.first {
                        $0.account?.id == account.id && $0.folderType == FolderType.inbox.rawValue
                    }
                    guard let inbox else { return }

                    let stream = monitor.monitor(accountId: account.id, folderImapPath: inbox.imapPath)
                    for await event in stream {
                        guard !Task.isCancelled else { break }
                        if case .newMail = event {
                            let result = try? await syncEmails.syncFolder(
                                accountId: account.id,
                                folderId: inbox.id,
                                options: .incremental
                            )
                            let syncedEmails = result?.newEmails ?? []
                            runAIClassification(for: syncedEmails)
                            if selectedAccount?.id == account.id {
                                await loadThreadsAndCounts()
                            }
                            await notificationCoordinator.didSyncNewEmails(
                                syncedEmails,
                                fromBackground: false
                            )
                            retryDelay = .seconds(2)
                        }
                    }
                    guard !Task.isCancelled else { break }
                    try? await Task.sleep(for: retryDelay)
                    retryDelay = min(retryDelay * 2, .seconds(30))
                }
            }
        }
    }

    private func stopIDLEMonitor() {
        for task in idleTasks.values {
            task.cancel()
        }
        idleTasks.removeAll()
    }

    // MARK: - Sidebar Account Actions

    /// Adds a new account from the sidebar.
    ///
    /// When multi-provider support is available, shows the ProviderSelectionView
    /// sheet. Otherwise falls back to legacy OAuth-only flow.
    private func addAccountFromSidebar() async {
        if providerDiscovery != nil && connectionTestUseCase != nil {
            showProviderSelection = true
        } else {
            // Legacy OAuth-only flow
            do {
                let newAccount = try await manageAccounts.addAccountViaOAuth()
                let freshAccounts = try await manageAccounts.getAccounts()
                accounts = freshAccounts

                isSyncing = true
                syncTask?.cancel()
                syncTask = Task {
                    defer { isSyncing = false; syncTask = nil }
                    let isSelected = selectedAccount?.id == newAccount.id
                    await syncSingleAccount(newAccount.id, isSelected: isSelected)
                }

                NotificationCenter.default.post(name: AppConstants.accountsDidChangeNotification, object: nil)
            } catch {
                // OAuth cancelled or failed
            }
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
                do {
                    try await composeEmail.executeSend(emailId: emailId)
                    NSLog("[UI] executeSend completed successfully for \(emailId)")
                } catch {
                    NSLog("[UI] executeSend FAILED for \(emailId): \(error)")
                }
                AttachmentPickerView.cleanupTempAttachments()
            }
        case .savedDraft, .discarded, .cancelled:
            break
        }
    }

    // MARK: - Search

    private func performSearch() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isSearchActive = false
            isSearchLoading = false
            searchThreads = []
            return
        }

        guard let searchUseCase else {
            isSearchActive = true
            isSearchLoading = false
            searchThreads = []
            return
        }

        isSearchActive = true
        isSearchLoading = true

        let query = SearchQueryParser.parse(trimmed, scope: .allMail)
        let engine = await aiEngineResolver?.resolveGenerativeEngine()
        let results = await searchUseCase.execute(query: query, engine: engine)

        guard !Task.isCancelled else { return }

        var seenThreadIds = Set<String>()
        var orderedThreadIds: [String] = []
        for result in results {
            if seenThreadIds.insert(result.threadId).inserted {
                orderedThreadIds.append(result.threadId)
            }
        }

        let fetchedThreads = fetchThreadsForSearch(ids: orderedThreadIds)
        let threadMap = Dictionary(uniqueKeysWithValues: fetchedThreads.map { ($0.id, $0) })
        searchThreads = orderedThreadIds.compactMap { threadMap[$0] }

        // Fallback for stale/empty FTS index: local SwiftData text scan.
        if searchThreads.isEmpty {
            let fallbackThreadIds = fetchFallbackThreadIds(query: trimmed)
            let fallbackThreads = fetchThreadsForSearch(ids: fallbackThreadIds)
            let fallbackMap = Dictionary(uniqueKeysWithValues: fallbackThreads.map { ($0.id, $0) })
            searchThreads = fallbackThreadIds.compactMap { fallbackMap[$0] }
        }

        isSearchLoading = false
    }

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

    private func fetchFallbackThreadIds(query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }

        let descriptor = FetchDescriptor<Email>()
        guard let emails = try? modelContext.fetch(descriptor) else { return [] }

        var seen = Set<String>()
        var ids: [String] = []
        for email in emails {
            let haystacks = [
                email.subject,
                email.fromAddress,
                email.fromName ?? "",
                email.snippet ?? "",
                email.bodyPlain ?? "",
            ]

            let matches = haystacks.contains { field in
                field.lowercased().contains(q)
            }
            guard matches else { continue }

            let threadId = email.threadId
            if seen.insert(threadId).inserted {
                ids.append(threadId)
            }
        }
        return ids
    }

    /// Keeps macOS in parity with iOS: synced emails are enqueued for AI
    /// processing, which also updates search indexes for new content.
    private func runAIClassification(for syncedEmails: [Email]) {
        guard let queue = aiProcessingQueue else { return }
        let sorted = syncedEmails
            .sorted { ($0.dateReceived ?? .distantPast) < ($1.dateReceived ?? .distantPast) }
        guard !sorted.isEmpty else { return }
        queue.enqueue(emails: sorted)
    }
}

enum MacPaginationRuleEngine {
    static func shouldAttemptCatchUp(
        hasMorePages: Bool,
        isUnifiedMode: Bool,
        isSearchActive: Bool,
        hasSelectedFolder: Bool,
        isOutboxSelected: Bool,
        folderType: String?,
        folderImapPath: String?
    ) -> Bool {
        guard !hasMorePages else { return false }
        guard !isUnifiedMode else { return false }
        guard !isSearchActive else { return false }
        guard hasSelectedFolder else { return false }
        guard !isOutboxSelected else { return false }
        guard let folderType, let folderImapPath else { return false }
        return isSyncableFolder(folderType: folderType, imapPath: folderImapPath)
    }

    static func shouldShowSentinel(
        hasMorePages: Bool,
        isCatchUpEligibleContext: Bool,
        reachedServerHistoryBoundary: Bool
    ) -> Bool {
        hasMorePages || (isCatchUpEligibleContext && !reachedServerHistoryBoundary)
    }

    static func isSyncableFolder(folderType: String, imapPath: String) -> Bool {
        guard !imapPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return FolderType(rawValue: folderType) != nil
    }
}

private struct SearchDebounceTrigger: Equatable {
    let text: String
    let selectedFolderId: String?
    let selectedAccountId: String?
}
#endif
