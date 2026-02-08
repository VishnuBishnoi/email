import SwiftUI
#if os(iOS)
import QuickLook
#endif

/// The threaded conversation detail screen.
///
/// Opened from `ThreadListView` when the user taps a thread. Displays all
/// messages in chronological order with expand/collapse, mark-as-read on open,
/// thread-level actions (reply, archive, delete, star), AI integration
/// (summary + smart reply), and large-thread pagination.
///
/// Architecture: MV pattern — view state managed via @State, use cases
/// injected as `let` properties. No ViewModel.
///
/// Spec ref: FR-ED-01, FR-ED-02, FR-ED-05
public struct EmailDetailView: View {

    // MARK: - Use Case Dependencies

    let threadId: String
    let fetchEmailDetail: FetchEmailDetailUseCaseProtocol
    let markRead: MarkReadUseCaseProtocol
    let manageThreadActions: ManageThreadActionsUseCaseProtocol
    let downloadAttachment: DownloadAttachmentUseCaseProtocol
    let summarizeThread: SummarizeThreadUseCaseProtocol?
    let smartReply: SmartReplyUseCaseProtocol?

    // MARK: - View State

    enum ViewState: Equatable {
        case loading
        case loaded
        case error(String)
        case offline
        case empty

        static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.loaded, .loaded),
                 (.offline, .offline), (.empty, .empty):
                return true
            case let (.error(a), .error(b)):
                return a == b
            default:
                return false
            }
        }
    }

    @State private var viewState: ViewState = .loading
    @State private var thread: Thread?
    @State private var sortedEmails: [Email] = []
    @State private var expandedEmailIds: Set<String> = []

    // MARK: - AI State

    @State private var aiSummary: String?
    @State private var aiSummaryLoading = false
    @State private var smartReplySuggestions: [String] = []

    // MARK: - Action State

    @State private var undoAction: UndoableAction?
    @State private var showUndoToast = false
    @State private var undoTask: Task<Void, Never>?
    @State private var errorToast: String?

    // MARK: - Attachment Preview

    @State private var previewURL: URL?
    @State private var showPreview = false

    // MARK: - Large Thread Pagination (FR-ED-05)

    @State private var displayedEmailCount = 25
    private let pageSize = 25
    private let paginationThreshold = 50

    // MARK: - Navigation

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    public var body: some View {
        Group {
            switch viewState {
            case .loading:
                loadingView
            case .loaded:
                loadedView
            case .error(let message):
                errorView(message: message)
            case .offline:
                offlineView
            case .empty:
                emptyView
            }
        }
        .navigationTitle(thread?.subject ?? "Conversation")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .task { await loadThread() }
        .task(id: thread?.id) { await loadAIContent() }
        .overlay(alignment: .bottom) {
            if showUndoToast, let action = undoAction {
                undoToastView(action: action)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let error = errorToast {
                errorToastView(message: error)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showPreview) {
            if let url = previewURL {
                AttachmentPreviewView(url: url)
            }
        }
        #endif
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading conversation…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading conversation")
    }

    // MARK: - Loaded View

    private var loadedView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    // AI Summary (FR-ED-02)
                    AISummaryView(
                        summary: aiSummary,
                        isLoading: aiSummaryLoading
                    )
                    .padding(.horizontal)

                    // "Show earlier messages" button (FR-ED-05)
                    if sortedEmails.count > displayedEmailCount {
                        showEarlierButton
                            .padding(.horizontal)
                    }

                    // Messages
                    ForEach(displayedEmails, id: \.id) { email in
                        MessageBubbleView(
                            email: email,
                            isExpanded: expandedEmailIds.contains(email.id),
                            isTrustedSender: false, // TODO: check TrustedSender
                            onToggleExpand: { toggleExpand(email.id) },
                            onStarToggle: { Task { await toggleStar(email) } },
                            onPreviewAttachment: { previewAttachment($0) },
                            onShareAttachment: { shareAttachment($0) },
                            downloadUseCase: downloadAttachment
                        )
                        .padding(.horizontal)
                        .id(email.id)
                    }

                    // Smart Reply Suggestions (FR-ED-02)
                    if !smartReplySuggestions.isEmpty {
                        SmartReplyView(
                            suggestions: smartReplySuggestions,
                            onTap: { suggestion in
                                // TODO: Navigate to composer with pre-filled text
                            }
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Couldn't load this conversation")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await loadThread() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error loading conversation. \(message)")
    }

    // MARK: - Offline View

    private var offlineView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("You're offline")
                .font(.headline)

            Text("Message body not available offline")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("This conversation appears empty")
                .font(.headline)

            Button("Go Back") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Show Earlier Button (FR-ED-05)

    private var showEarlierButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                displayedEmailCount += pageSize
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.circle")
                Text("Show \(min(pageSize, sortedEmails.count - displayedEmailCount)) earlier messages")
            }
            .font(.subheadline)
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(red: 0.95, green: 0.95, blue: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel("Show earlier messages in this conversation")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                // TODO: Navigate to composer — Reply
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
            }
            .accessibilityLabel("Reply")

            Spacer()

            Button {
                // TODO: Navigate to composer — Reply All
            } label: {
                Image(systemName: "arrowshape.turn.up.left.2")
            }
            .accessibilityLabel("Reply All")

            Spacer()

            Button {
                // TODO: Navigate to composer — Forward
            } label: {
                Image(systemName: "arrowshape.turn.up.right")
            }
            .accessibilityLabel("Forward")

            Spacer()

            Menu {
                Button(role: .destructive) {
                    Task { await archiveThread() }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }

                Button(role: .destructive) {
                    Task { await deleteThread() }
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    Task { await markUnread() }
                } label: {
                    Label("Mark Unread", systemImage: "envelope.badge")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More actions")
        }
        #else
        ToolbarItemGroup(placement: .automatic) {
            Button {
                // TODO: Navigate to composer — Reply
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
            }
            .accessibilityLabel("Reply")

            Menu {
                Button(role: .destructive) {
                    Task { await archiveThread() }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }

                Button(role: .destructive) {
                    Task { await deleteThread() }
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    Task { await markUnread() }
                } label: {
                    Label("Mark Unread", systemImage: "envelope.badge")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More actions")
        }
        #endif
    }

    // MARK: - Undo Toast

    private func undoToastView(action: UndoableAction) -> some View {
        HStack {
            Text(action.message)
                .font(.subheadline)
                .foregroundStyle(.white)

            Spacer()

            Button("Undo") {
                performUndo(action)
            }
            .font(.subheadline.bold())
            .foregroundStyle(.yellow)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(white: 0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Error Toast

    private func errorToastView(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.red)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation { errorToast = nil }
            }
        }
    }

    // MARK: - Data Loading

    private func loadThread() async {
        viewState = .loading

        do {
            let loadedThread = try await fetchEmailDetail.fetchThread(threadId: threadId)
            thread = loadedThread

            let emails = loadedThread.emails
                .sorted { ($0.dateReceived ?? .distantPast) < ($1.dateReceived ?? .distantPast) }
            sortedEmails = emails

            guard !emails.isEmpty else {
                viewState = .empty
                return
            }

            // Auto-expand logic (FR-ED-01):
            // Collapse read messages, expand latest unread.
            // If all read, expand only the latest.
            expandedEmailIds.removeAll()

            let unreadEmails = emails.filter { !$0.isRead }
            if let latestUnread = unreadEmails.last {
                expandedEmailIds.insert(latestUnread.id)
            } else if let latest = emails.last {
                expandedEmailIds.insert(latest.id)
            }

            // Pagination: show all if under threshold, otherwise latest 25
            if emails.count > paginationThreshold {
                displayedEmailCount = pageSize
            } else {
                displayedEmailCount = emails.count
            }

            viewState = .loaded

            // Mark as read (FR-ED-01: immediate on open)
            await markAllRead()

        } catch let error as EmailDetailError {
            switch error {
            case .threadNotFound:
                viewState = .empty
            default:
                viewState = .error(error.localizedDescription)
            }
        } catch {
            viewState = .error(error.localizedDescription)
        }
    }

    private func markAllRead() async {
        guard let thread, thread.unreadCount > 0 else { return }
        do {
            try await markRead.markAllRead(in: thread)
        } catch {
            withAnimation {
                errorToast = "Couldn't mark as read. Tap to retry."
            }
        }
    }

    // MARK: - AI Content (FR-ED-02)

    private func loadAIContent() async {
        guard let thread else { return }

        // Summary
        if let summarize = summarizeThread {
            aiSummaryLoading = true
            aiSummary = await summarize.summarize(thread: thread)
            aiSummaryLoading = false
        }

        // Smart replies (from latest email)
        if let reply = smartReply, let latestEmail = sortedEmails.last {
            smartReplySuggestions = await reply.generateReplies(for: latestEmail)
        }
    }

    // MARK: - Expand/Collapse

    private func toggleExpand(_ emailId: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if expandedEmailIds.contains(emailId) {
                expandedEmailIds.remove(emailId)
            } else {
                expandedEmailIds.insert(emailId)
            }
        }
    }

    // MARK: - Star Toggle

    private func toggleStar(_ email: Email) async {
        do {
            try await manageThreadActions.toggleStarStatus(threadId: email.threadId)
        } catch {
            withAnimation {
                errorToast = "Couldn't update star."
            }
        }
    }

    // MARK: - Thread Actions

    private func archiveThread() async {
        guard let thread else { return }
        let action = UndoableAction(
            type: .archive,
            threadId: thread.id,
            message: "Conversation archived"
        )
        showUndoAndSchedule(action)

        do {
            try await manageThreadActions.archiveThread(id: thread.id)
            // Navigate back after action
            dismiss()
        } catch {
            cancelUndo()
            withAnimation {
                errorToast = "Couldn't archive. Tap to retry."
            }
        }
    }

    private func deleteThread() async {
        guard let thread else { return }
        let action = UndoableAction(
            type: .delete,
            threadId: thread.id,
            message: "Conversation deleted"
        )
        showUndoAndSchedule(action)

        do {
            try await manageThreadActions.deleteThread(id: thread.id)
            dismiss()
        } catch {
            cancelUndo()
            withAnimation {
                errorToast = "Couldn't delete. Tap to retry."
            }
        }
    }

    private func markUnread() async {
        guard let thread else { return }
        do {
            try await manageThreadActions.toggleReadStatus(threadId: thread.id)
            dismiss()
        } catch {
            withAnimation {
                errorToast = "Couldn't mark as unread."
            }
        }
    }

    // MARK: - Undo Support

    private func showUndoAndSchedule(_ action: UndoableAction) {
        undoAction = action
        withAnimation { showUndoToast = true }

        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation {
                showUndoToast = false
                undoAction = nil
            }
        }
    }

    private func performUndo(_ action: UndoableAction) {
        undoTask?.cancel()
        withAnimation {
            showUndoToast = false
            undoAction = nil
        }
        // Undo logic would reverse the action — for V1, reloading the thread
        Task { await loadThread() }
    }

    private func cancelUndo() {
        undoTask?.cancel()
        withAnimation {
            showUndoToast = false
            undoAction = nil
        }
    }

    // MARK: - Attachment Actions

    private func previewAttachment(_ attachment: Attachment) {
        guard let path = attachment.localPath else { return }
        previewURL = URL(fileURLWithPath: path)
        showPreview = true
    }

    private func shareAttachment(_ url: URL) {
        // System share handled at the AttachmentRowView level
    }

    // MARK: - Computed

    private var displayedEmails: [Email] {
        if sortedEmails.count <= displayedEmailCount {
            return sortedEmails
        }
        // Show the latest N emails
        let startIndex = max(0, sortedEmails.count - displayedEmailCount)
        return Array(sortedEmails[startIndex...])
    }
}

// MARK: - Supporting Types

/// Represents an undoable thread action.
struct UndoableAction: Equatable {
    enum ActionType: Equatable {
        case archive
        case delete
    }

    let type: ActionType
    let threadId: String
    let message: String
}
