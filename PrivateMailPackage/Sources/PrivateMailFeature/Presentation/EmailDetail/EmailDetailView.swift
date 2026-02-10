import SwiftUI
#if os(iOS)
import QuickLook
import UIKit
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
    let composeEmail: ComposeEmailUseCaseProtocol?
    let queryContacts: QueryContactsUseCaseProtocol?
    let accounts: [Account]

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

    // MARK: - Composer State

    @State private var composerMode: ComposerMode?
    @State private var composerInitialBody: String?

    // MARK: - Attachment Preview

    @State private var previewURL: URL?
    @State private var showPreview = false

    // MARK: - Trusted Senders (FR-ED-04)

    @State private var trustedSenderEmails: Set<String> = []

    // MARK: - Large Thread Pagination (FR-ED-05)

    @State private var displayedEmailCount = 25
    private let pageSize = 25
    private let paginationThreshold = 50

    // MARK: - Network (PR #8 Comment 7)

    #if os(iOS)
    @State private var networkMonitor = NetworkMonitor()
    #endif

    // MARK: - Navigation

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        #if os(iOS)
        .environment(networkMonitor)
        #endif
        .navigationTitle(thread?.subject ?? "Conversation")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .task { await loadThread() }
        .task(id: thread?.id) { await loadSmartReplies() }
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
        .sheet(item: $composerMode) { mode in
            if let composeEmail, let queryContacts {
                ComposerView(
                    composeEmail: composeEmail,
                    queryContacts: queryContacts,
                    smartReply: smartReply ?? SmartReplyUseCase(aiRepository: StubAIRepository()),
                    mode: mode,
                    accounts: accounts,
                    initialBody: composerInitialBody,
                    onDismiss: { _ in
                        composerMode = nil
                        composerInitialBody = nil
                    }
                )
            }
        }
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
        .accessibilityIdentifier("email-detail-loading")
    }

    // MARK: - Loaded View

    /// Whether any email in the thread is flagged as spam.
    private var hasSpamEmails: Bool {
        sortedEmails.contains { $0.isSpam }
    }

    private var loadedView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Spam/phishing warning banner (FR-AI-06)
                    if hasSpamEmails {
                        spamWarningBanner
                            .padding(.horizontal)
                    }

                    // AI Summary — on-demand only (FR-ED-02)
                    AISummaryView(
                        summary: aiSummary,
                        isLoading: aiSummaryLoading,
                        isAvailable: summarizeThread != nil,
                        onRequestSummary: { Task { await generateSummary() } }
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
                            isTrustedSender: trustedSenderEmails.contains(email.fromAddress),
                            onToggleExpand: { toggleExpand(email.id) },
                            onStarToggle: { Task { await toggleStar(email) } },
                            onPreviewAttachment: { previewAttachment($0) },
                            onShareAttachment: { shareAttachment($0) },
                            onAlwaysLoadImages: { Task { await addTrustedSender(email.fromAddress) } },
                            downloadUseCase: downloadAttachment
                        )
                        .padding(.horizontal)
                        .id(email.id)
                        .accessibilityIdentifier("message-bubble-\(email.id)")
                    }

                    // Smart Reply Suggestions (FR-ED-02)
                    if !smartReplySuggestions.isEmpty {
                        SmartReplyView(
                            suggestions: smartReplySuggestions,
                            onTap: { suggestion in
                                composerInitialBody = suggestion
                                openComposer { .reply(email: $0) }
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
        .accessibilityIdentifier("email-detail-error")
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
            let animation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.3)
            withAnimation(animation) {
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

    // MARK: - Composer Navigation

    /// Open the composer for the latest email in the thread.
    ///
    /// Converts the latest `Email` to a `ComposerEmailContext` snapshot
    /// and sets `composerMode` to trigger the sheet.
    private func openComposer(mode: (ComposerEmailContext) -> ComposerMode) {
        guard let email = sortedEmails.last else { return }
        let context = ComposerEmailContext(from: email)
        composerMode = mode(context)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                openComposer { .reply(email: $0) }
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
            }
            .accessibilityLabel("Reply")

            Spacer()

            Button {
                openComposer { .replyAll(email: $0) }
            } label: {
                Image(systemName: "arrowshape.turn.up.left.2")
            }
            .accessibilityLabel("Reply All")

            Spacer()

            Button {
                openComposer { .forward(email: $0) }
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
                openComposer { .reply(email: $0) }
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
        .task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { errorToast = nil }
        }
    }

    // MARK: - Data Loading

    private func loadThread() async {
        viewState = .loading

        // Load trusted senders (FR-ED-04)
        if let senders = try? await fetchEmailDetail.getAllTrustedSenderEmails() {
            trustedSenderEmails = senders
        }

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

            // Pagination: show all if under threshold, otherwise latest 25.
            // PR #8 Comment 2: Ensure the latest unread is within the initial window.
            if emails.count > paginationThreshold {
                displayedEmailCount = pageSize

                // Expand window to include the latest unread email if it's
                // outside the default tail window.
                if let latestUnread = unreadEmails.last,
                   let unreadIndex = emails.firstIndex(where: { $0.id == latestUnread.id }) {
                    let startIndex = emails.count - displayedEmailCount
                    if unreadIndex < startIndex {
                        displayedEmailCount = emails.count - unreadIndex
                    }
                }
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

    /// Generate AI summary on-demand (user-initiated only).
    ///
    /// Checks for a cached summary first; if none exists, generates one
    /// via the summarize use case. Only called when the user taps
    /// the "Summarize with AI" button.
    private func generateSummary() async {
        guard let thread else { return }

        // Use cached summary if available
        if let cached = thread.aiSummary, !cached.isEmpty {
            aiSummary = cached
            return
        }

        guard let summarize = summarizeThread else { return }

        aiSummaryLoading = true
        let result = await summarize.summarize(thread: thread)
        aiSummary = (result?.isEmpty == false) ? result : nil
        aiSummaryLoading = false
    }

    /// Load smart reply suggestions automatically when the thread loads.
    private func loadSmartReplies() async {
        guard let _ = thread else { return }

        // Show cached summary if already generated
        if let cached = thread?.aiSummary, !cached.isEmpty {
            aiSummary = cached
        }

        // Smart replies (from latest email)
        if let reply = smartReply, let latestEmail = sortedEmails.last {
            smartReplySuggestions = await reply.generateReplies(for: latestEmail)
        }
    }

    // MARK: - Trusted Sender Actions

    private func addTrustedSender(_ senderEmail: String) async {
        do {
            try await fetchEmailDetail.saveTrustedSender(email: senderEmail)
            trustedSenderEmails.insert(senderEmail)
        } catch {
            withAnimation {
                errorToast = "Couldn't save trusted sender."
            }
        }
    }

    // MARK: - Expand/Collapse

    private func toggleExpand(_ emailId: String) {
        let animation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.25)
        withAnimation(animation) {
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
            // PR #8 Comment 1: Toggle at email-level, not thread-level.
            // Repository recalculates Thread.isStarred automatically.
            try await manageThreadActions.toggleEmailStarStatus(emailId: email.id)
        } catch {
            withAnimation {
                errorToast = "Couldn't update star."
            }
        }
    }

    // MARK: - Thread Actions

    private func archiveThread() async {
        guard let thread else { return }

        // Perform the action immediately and dismiss.
        // The undo toast is unreachable once the view dismisses, so
        // skip it for now (V1) — future work can surface undo in the
        // parent ThreadListView via a callback.
        do {
            try await manageThreadActions.archiveThread(id: thread.id)
            dismiss()
        } catch {
            withAnimation {
                errorToast = "Couldn't archive. Tap to retry."
            }
        }
    }

    private func deleteThread() async {
        guard let thread else { return }

        do {
            try await manageThreadActions.deleteThread(id: thread.id)
            dismiss()
        } catch {
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

    // MARK: - Spam Warning Banner (FR-AI-06)

    private var spamWarningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.white)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("This message looks suspicious")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("It may be spam or a phishing attempt")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            Button("Not Spam") {
                markThreadAsNotSpam()
            }
            .font(.caption.bold())
            .foregroundStyle(.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .background(.red, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: this message may be spam or phishing. Tap Not Spam to override.")
    }

    /// Clear the spam flag on all emails in the thread.
    private func markThreadAsNotSpam() {
        for email in sortedEmails where email.isSpam {
            email.isSpam = false
        }
    }

    // MARK: - Attachment Actions

    private func previewAttachment(_ attachment: Attachment) {
        guard let path = attachment.localPath else { return }
        previewURL = URL(fileURLWithPath: path)
        showPreview = true
    }

    private func shareAttachment(_ url: URL) {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return
        }
        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        // iPad popover anchor
        activityVC.popoverPresentationController?.sourceView = rootVC.view
        activityVC.popoverPresentationController?.sourceRect = CGRect(
            x: rootVC.view.bounds.midX,
            y: rootVC.view.bounds.midY,
            width: 0,
            height: 0
        )
        rootVC.present(activityVC, animated: true)
        #endif
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
