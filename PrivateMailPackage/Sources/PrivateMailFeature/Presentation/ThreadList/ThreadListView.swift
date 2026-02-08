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

    // Account switcher placeholder
    @State private var showAccountSwitcher = false

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

    /// Whether to show category tabs (hidden for Outbox and when no categories visible).
    private var showCategoryTabs: Bool {
        guard !isOutboxSelected else { return false }
        // Show if at least one category is visible in settings
        let hasVisibleCategories = settings.categoryTabVisibility.values.contains(true)
        return hasVisibleCategories
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
            .alert("Switch Account", isPresented: $showAccountSwitcher) {
                accountSwitcherButtons
            } message: {
                Text("Select an account to view")
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
        List {
            ForEach(threads, id: \.id) { thread in
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
                // TODO: Add swipe actions for read/unread toggle, star, move (Phase 6 integration)
            }

            // Pagination sentinel
            if hasMorePages {
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
        .listStyle(.plain)
        .refreshable {
            await reloadThreads()
        }
        .navigationDestination(for: String.self) { threadId in
            if let thread = threads.first(where: { $0.id == threadId }) {
                EmailDetailPlaceholder(threadSubject: thread.subject)
            }
        }
        .accessibilityLabel("Email threads")
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
                            selectedFolder = folder
                            selectedCategory = nil
                            Task { await reloadThreads() }
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

        // TODO: Add multi-select toolbar (Phase 6 integration)
    }

    // MARK: - Account Switcher Alert Buttons

    @ViewBuilder
    private var accountSwitcherButtons: some View {
        // "All Accounts" unified option
        Button("All Accounts") {
            selectedAccount = nil
            selectedFolder = nil
            selectedCategory = nil
            Task { await reloadThreads() }
        }

        // Individual accounts
        ForEach(accounts, id: \.id) { account in
            Button(account.email) {
                selectedAccount = account
                selectedFolder = nil
                selectedCategory = nil
                Task { await switchToAccount(account) }
            }
        }

        Button("Cancel", role: .cancel) {}
    }

    // MARK: - Data Loading

    /// Initial load on view appear: load accounts, select first, load folders + threads.
    private func initialLoad() async {
        viewState = .loading

        do {
            // Load accounts
            accounts = try await manageAccounts.getAccounts()

            guard let firstAccount = accounts.first else {
                viewState = .empty
                return
            }

            // Default to first account
            selectedAccount = firstAccount

            // Load folders for the selected account
            folders = try await fetchThreads.fetchFolders(accountId: firstAccount.id)

            // Select inbox folder by default
            let inboxType = FolderType.inbox.rawValue
            selectedFolder = folders.first(where: { $0.folderType == inboxType }) ?? folders.first

            // Load threads and unread counts
            await loadThreadsAndCounts()
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
            viewState = .error(error.localizedDescription)
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
            // Pagination errors don't replace the whole view state
            // Just stop paginating silently
            hasMorePages = false
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
