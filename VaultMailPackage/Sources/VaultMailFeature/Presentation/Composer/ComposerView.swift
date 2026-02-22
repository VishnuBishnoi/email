import SwiftUI

/// Email composition screen with all four modes and full lifecycle.
///
/// MV pattern: all state managed via @State, no ViewModel.
/// Views call use cases only (FR-FOUND-01).
///
/// Supports: new, reply, reply-all, forward, edit-draft modes.
/// Handles: send validation, discard confirmation, auto-save,
/// smart reply suggestions, attachment management.
///
/// Spec ref: Email Composer FR-COMP-01..04, NFR-COMP-01..04
public struct ComposerView: View {
    // MARK: - Dependencies (Use Cases)

    let composeEmail: ComposeEmailUseCaseProtocol
    let queryContacts: QueryContactsUseCaseProtocol
    let smartReply: SmartReplyUseCaseProtocol
    let mode: ComposerMode
    let accounts: [Account]
    let initialBody: String?
    let onDismiss: @MainActor (ComposerDismissResult) -> Void

    @Environment(ThemeProvider.self) private var theme
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    // MARK: - Composition State

    @State private var toRecipients: [RecipientToken] = []
    @State private var ccRecipients: [RecipientToken] = []
    @State private var bccRecipients: [RecipientToken] = []
    @State private var subject: String = ""
    @State private var bodyText: String = ""
    @State private var attachments: [AttachmentItem] = []

    // MARK: - UI State

    @State private var showCC = false
    @State private var showBCC = false
    @State private var viewState: ComposerViewState = .composing
    @State private var draftId: String? = nil
    @State private var lastSavedContent: String = ""
    @State private var showDiscardAlert = false
    @State private var showEmptySubjectAlert = false
    @State private var showEmptyBodyAlert = false
    @State private var errorMessage: String? = nil
    @State private var smartReplies: [String] = []

    // MARK: - View State Enum

    enum ComposerViewState: Equatable {
        case composing
        case saving
        case sending
    }

    // MARK: - Derived State

    /// Whether the composer has any user content.
    private var hasContent: Bool {
        !toRecipients.isEmpty || !ccRecipients.isEmpty || !bccRecipients.isEmpty ||
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !bodyTextWithoutQuote.isEmpty ||
        !attachments.isEmpty
    }

    /// Body text excluding quoted content from reply/forward prefill.
    private var bodyTextWithoutQuote: String {
        // Simple heuristic: user-typed content is before the quoted block
        if let range = bodyText.range(of: "\n\n>") {
            return String(bodyText[bodyText.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = bodyText.range(of: "\n\n----------") {
            return String(bodyText[bodyText.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The Account matching the current composition mode.
    private var fromAccount: Account? {
        accounts.first { $0.id == mode.accountId }
    }

    /// Whether the send button should be enabled.
    private var canSend: Bool {
        let allRecipients = toRecipients + ccRecipients + bccRecipients
        let hasRecipient = !allRecipients.isEmpty
        let maxBytes = AppConstants.maxAttachmentSizeMB * 1024 * 1024
        let notOverSize = totalAttachmentBytes <= maxBytes
        return hasRecipient && notOverSize && viewState == .composing
    }

    /// Total attachment size in bytes.
    private var totalAttachmentBytes: Int {
        attachments.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Account IDs for contact queries.
    private var accountIds: [String] {
        [mode.accountId]
    }

    /// Navigation title based on mode.
    private var navigationTitle: String {
        switch mode {
        case .new: "New Email"
        case .reply: "Reply"
        case .replyAll: "Reply All"
        case .forward: "Forward"
        case .editDraft: "Draft"
        }
    }

    /// Whether this is a reply mode (for smart replies).
    private var isReplyMode: Bool {
        switch mode {
        case .reply, .replyAll: true
        default: false
        }
    }

    /// A content fingerprint for detecting changes (used by auto-save).
    private var contentFingerprint: String {
        let recipientStr = (toRecipients + ccRecipients + bccRecipients).map(\.email).joined()
        return "\(recipientStr)|\(subject)|\(bodyText)|\(attachments.map(\.id).joined())"
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // From account (read-only)
                    fromRow

                    // To recipients
                    RecipientFieldView(
                        label: "To",
                        recipients: $toRecipients,
                        queryContacts: queryContacts,
                        accountIds: accountIds
                    )

                    // CC/BCC toggle
                    if !showCC && !showBCC {
                        ccBccToggle
                    }

                    // CC field
                    if showCC {
                        RecipientFieldView(
                            label: "Cc",
                            recipients: $ccRecipients,
                            queryContacts: queryContacts,
                            accountIds: accountIds
                        )
                    }

                    // BCC field
                    if showBCC {
                        RecipientFieldView(
                            label: "Bcc",
                            recipients: $bccRecipients,
                            queryContacts: queryContacts,
                            accountIds: accountIds
                        )
                    }

                    // Subject
                    subjectField

                    // Smart reply chips (reply modes only)
                    if isReplyMode && !smartReplies.isEmpty {
                        SmartReplyChipView(replies: smartReplies) { reply in
                            if bodyTextWithoutQuote.isEmpty {
                                // Insert before quoted text
                                if let range = bodyText.range(of: "\n\n>") {
                                    bodyText = reply + String(bodyText[range.lowerBound...])
                                } else {
                                    bodyText = reply + bodyText
                                }
                            } else {
                                bodyText = reply + bodyText
                            }
                            smartReplies = []
                        }
                    }

                    // Body editor
                    BodyEditorView(text: $bodyText)

                    // Attachments
                    AttachmentPickerView(attachments: $attachments)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { composerToolbar }
            .alert("No Subject", isPresented: $showEmptySubjectAlert) {
                Button("Send Anyway") {
                    Task { await performSend() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Send without a subject?")
            }
            .alert("No Message", isPresented: $showEmptyBodyAlert) {
                Button("Send Anyway") {
                    if subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Both empty — still send
                    }
                    Task { await performSend() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Send an empty message?")
            }
            .confirmationDialog("", isPresented: $showDiscardAlert, titleVisibility: .hidden) {
                Button("Delete Draft", role: .destructive) {
                    Task { await handleDiscard() }
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Delete this draft?")
            }
            .interactiveDismissDisabled(hasContent)
            // Error banner
            .overlay(alignment: .bottom) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textInverse)
                        .padding(.horizontal, theme.spacing.lg)
                        .padding(.vertical, theme.spacing.sm)
                        .background(theme.colors.destructive, in: theme.shapes.smallRect)
                        .padding()
                        .transition(.move(edge: .bottom))
                        .task {
                            try? await Task.sleep(for: .seconds(3))
                            self.errorMessage = nil
                        }
                }
            }
        }
        .task {
            await prefillFromMode()
        }
        .task(id: draftId) {
            await autoSaveLoop()
        }
    }

    // MARK: - From Row

    private var fromRow: some View {
        HStack {
            Text("From")
                .font(theme.typography.bodyMedium)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 36, alignment: .leading)

            if let account = fromAccount {
                VStack(alignment: .leading, spacing: 1) {
                    if !account.displayName.isEmpty {
                        Text(account.displayName)
                            .font(theme.typography.bodyMedium)
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                    Text(account.email)
                        .font(account.displayName.isEmpty ? theme.typography.bodyMedium : theme.typography.caption)
                        .foregroundStyle(account.displayName.isEmpty ? theme.colors.textPrimary : theme.colors.textSecondary)
                }
            } else {
                Text(mode.accountId)
                    .font(theme.typography.bodyMedium)
                    .foregroundStyle(theme.colors.textPrimary)
            }

            Spacer()
        }
        .padding(.horizontal, theme.spacing.lg)
        .padding(.vertical, theme.spacing.listRowSpacing)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 52)
        }
    }

    // MARK: - CC/BCC Toggle

    private var ccBccToggle: some View {
        HStack {
            Spacer()
            Button("Cc/Bcc") {
                withAnimation {
                    showCC = true
                    showBCC = true
                }
            }
            .font(theme.typography.bodyMedium)
            .padding(.trailing, theme.spacing.lg)
            .padding(.vertical, theme.spacing.xs)
        }
    }

    // MARK: - Subject Field

    private var subjectField: some View {
        VStack(spacing: 0) {
            HStack(spacing: theme.spacing.xs) {
                Text("Subject")
                    .font(theme.typography.bodyMedium)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 56, alignment: .leading)

                TextField("", text: $subject)
                    .font(theme.typography.bodyMedium)
                    .accessibilityLabel("Subject")
            }
            .padding(.horizontal, theme.spacing.lg)
            .padding(.vertical, theme.spacing.listRowSpacing)

            Divider()
                .padding(.leading, theme.spacing.lg)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var composerToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                handleCancel()
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            if viewState == .sending {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await handleSend() }
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
    }

    // MARK: - Prefill

    private func prefillFromMode() async {
        // Get the user's email for self-deduplication in reply-all
        let userEmail = fromAccount?.email ?? mode.accountId

        let prefill = composeEmail.buildPrefill(mode: mode, userEmail: userEmail)

        toRecipients = prefill.toAddresses.map {
            RecipientToken(email: $0, isValid: RecipientFieldView.isValidEmail($0))
        }
        ccRecipients = prefill.ccAddresses.map {
            RecipientToken(email: $0, isValid: RecipientFieldView.isValidEmail($0))
        }
        bccRecipients = prefill.bccAddresses.map {
            RecipientToken(email: $0, isValid: RecipientFieldView.isValidEmail($0))
        }
        subject = prefill.subject

        // If a smart reply suggestion was selected from EmailDetailView,
        // prepend it before the quoted text from the prefill.
        if let initial = initialBody, !initial.isEmpty {
            if prefill.bodyPrefix.isEmpty {
                bodyText = initial
            } else {
                bodyText = initial + "\n\n" + prefill.bodyPrefix
            }
        } else {
            bodyText = prefill.bodyPrefix
        }

        // Show CC/BCC if prefilled
        if !ccRecipients.isEmpty { showCC = true }
        if !bccRecipients.isEmpty { showBCC = true }

        // TODO: Forward/draft attachment download not yet implemented.
        // Original attachments require IMAP FETCH to retrieve their bytes.
        // Until that path is wired, don't show placeholder tokens that would
        // silently be omitted from the outgoing MIME message (no localPath).

        // For draft editing, set the draft ID
        if case .editDraft(let ctx) = mode {
            draftId = ctx.emailId
        }

        // Record initial content for auto-save change detection
        lastSavedContent = contentFingerprint

        // Load smart replies for reply modes
        if isReplyMode {
            await loadSmartReplies()
        }
    }

    // MARK: - Smart Reply

    private func loadSmartReplies() async {
        switch mode {
        case .reply(let ctx), .replyAll(let ctx):
            let replies = await smartReply.generateReplies(for: ctx)
            if !replies.isEmpty {
                smartReplies = Array(replies.prefix(AppConstants.smartReplyMaxSuggestions))
            }
        default:
            break
        }
    }

    // MARK: - Auto-Save

    private func autoSaveLoop() async {
        // Wait for first meaningful edit before starting auto-save
        if draftId == nil && !hasContent {
            while !Task.isCancelled && !hasContent {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
        }

        // Auto-save loop: every 30 seconds
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(AppConstants.draftAutoSaveIntervalSeconds))
            guard !Task.isCancelled else { break }

            // Only save if content changed since last save
            let currentFingerprint = contentFingerprint
            guard currentFingerprint != lastSavedContent else { continue }

            await saveDraft()
            lastSavedContent = currentFingerprint
        }
    }

    // MARK: - Draft Save

    private func saveDraft() async {
        do {
            let id = try await composeEmail.saveDraft(
                draftId: draftId,
                accountId: mode.accountId,
                threadId: threadIdForMode,
                toAddresses: toRecipients.map(\.email),
                ccAddresses: ccRecipients.map(\.email),
                bccAddresses: bccRecipients.map(\.email),
                subject: subject,
                bodyPlain: bodyText,
                inReplyTo: inReplyToForMode,
                references: referencesForMode,
                attachments: attachments
            )
            draftId = id
        } catch {
            // Draft save failure is non-blocking per FR-COMP-01
            errorMessage = "Draft save failed"
        }
    }

    // MARK: - Send Flow

    private func handleSend() async {
        // Check empty subject
        if subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showEmptySubjectAlert = true
            return
        }

        // Check empty body
        if bodyTextWithoutQuote.isEmpty {
            showEmptyBodyAlert = true
            return
        }

        await performSend()
    }

    private func performSend() async {
        viewState = .sending

        do {
            // Save final draft state
            let emailId = try await composeEmail.saveDraft(
                draftId: draftId,
                accountId: mode.accountId,
                threadId: threadIdForMode,
                toAddresses: toRecipients.map(\.email),
                ccAddresses: ccRecipients.map(\.email),
                bccAddresses: bccRecipients.map(\.email),
                subject: subject,
                bodyPlain: bodyText,
                inReplyTo: inReplyToForMode,
                references: referencesForMode,
                attachments: attachments
            )

            // Queue for sending
            try await composeEmail.queueForSending(emailId: emailId)

            // NOTE: Do NOT clean up temp attachments here — executeSend() needs them
            // after the undo countdown. Cleanup happens in handleComposerDismiss.

            // Dismiss and notify parent to start undo countdown
            onDismiss(.sent(emailId: emailId))
            dismiss()
        } catch {
            viewState = .composing
            errorMessage = "Send failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Cancel / Discard

    private func handleCancel() {
        if hasContent {
            showDiscardAlert = true
        } else {
            onDismiss(.cancelled)
            dismiss()
        }
    }

    private func handleDiscard() async {
        // Delete draft if it was saved
        if let draftId {
            try? await composeEmail.deleteDraft(emailId: draftId)
        }
        // Clean up temp attachment files
        AttachmentPickerView.cleanupTempAttachments()
        onDismiss(.discarded)
        dismiss()
    }

    // MARK: - Mode Helpers

    private var threadIdForMode: String? {
        switch mode {
        case .new:
            return nil
        case .reply(let ctx), .replyAll(let ctx), .forward(let ctx), .editDraft(let ctx):
            return ctx.threadId
        }
    }

    private var inReplyToForMode: String? {
        switch mode {
        case .reply(let ctx), .replyAll(let ctx):
            return ctx.messageId
        case .editDraft(let ctx):
            return ctx.inReplyTo
        default:
            return nil
        }
    }

    private var referencesForMode: String? {
        switch mode {
        case .reply(let ctx), .replyAll(let ctx):
            var refs = ctx.references ?? ""
            if !refs.isEmpty { refs += " " }
            refs += ctx.messageId
            return refs
        case .editDraft(let ctx):
            return ctx.references
        default:
            return nil
        }
    }
}

// MARK: - Previews

#Preview("New Email") {
    ComposerView(
        composeEmail: PreviewComposeEmailUseCase(),
        queryContacts: PreviewQueryContactsUseCaseForComposer(),
        smartReply: PreviewSmartReplyUseCase(),
        mode: .new(accountId: "preview-acc"),
        accounts: [Account(id: "preview-acc", email: "user@gmail.com", displayName: "Preview User")],
        initialBody: nil,
        onDismiss: { _ in }
    )
    .environment(SettingsStore())
    .environment(ThemeProvider())
}

// MARK: - Preview Stubs

@MainActor
private final class PreviewComposeEmailUseCase: ComposeEmailUseCaseProtocol {
    func buildPrefill(mode: ComposerMode, userEmail: String) -> ComposerPrefill {
        ComposerPrefill()
    }
    func saveDraft(draftId: String?, accountId: String, threadId: String?, toAddresses: [String], ccAddresses: [String], bccAddresses: [String], subject: String, bodyPlain: String, inReplyTo: String?, references: String?, attachments: [AttachmentItem]) async throws -> String {
        UUID().uuidString
    }
    func queueForSending(emailId: String) async throws {}
    func undoSend(emailId: String) async throws {}
    func executeSend(emailId: String) async throws {}
    func deleteDraft(emailId: String) async throws {}
    func recoverStuckSendingEmails() async {}
}

@MainActor
private final class PreviewQueryContactsUseCaseForComposer: QueryContactsUseCaseProtocol {
    func queryContacts(prefix: String, accountIds: [String]) async throws -> [ContactCacheEntry] { [] }
}

@MainActor
private final class PreviewSmartReplyUseCase: SmartReplyUseCaseProtocol {
    func generateReplies(for email: Email) async -> [String] { [] }
    func generateReplies(for emailContext: ComposerEmailContext) async -> [String] { [] }
}
