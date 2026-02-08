import SwiftUI
import SwiftData

struct ComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let mode: ComposerMode
    let fromAccountId: String?
    let fromAccount: String?
    let initialSmartReplies: [String]

    @State private var toAddresses: [String] = []
    @State private var ccAddresses: [String] = []
    @State private var bccAddresses: [String] = []
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var attachments: [ComposerAttachmentDraft] = []

    @State private var showCC = false
    @State private var showBCC = false
    @State private var showDiscardConfirmation = false
    @State private var pendingPromptQueue: [ComposerSendPrompt] = []
    @State private var activePrompt: ComposerSendPrompt?
    @State private var smartReplies: [String] = []
    @State private var inReplyTo: String?
    @State private var references: String?
    @State private var isSending = false
    @State private var sendErrorMessage: String?

    @State private var initialLoaded = false

    init(
        mode: ComposerMode = .new,
        fromAccountId: String? = nil,
        fromAccount: String? = nil,
        initialSmartReplies: [String] = []
    ) {
        self.mode = mode
        self.fromAccountId = fromAccountId
        self.fromAccount = fromAccount
        self.initialSmartReplies = initialSmartReplies
    }

    private var totalAttachmentBytes: Int {
        attachments.reduce(0) { $0 + $1.sizeBytes }
    }

    private var sendValidation: ComposerSendValidation {
        ComposerSendValidator.validate(
            to: toAddresses,
            cc: ccAddresses,
            bcc: bccAddresses,
            attachmentTotalBytes: totalAttachmentBytes
        )
    }

    private var forwardAttachmentReadiness: ForwardAttachmentReadiness {
        ForwardAttachmentResolver.evaluateForwardReadiness(attachments: attachments)
    }

    private var canTapSend: Bool {
        sendValidation.canSend && forwardAttachmentReadiness.canSend && !isSending
    }

    private var invalidAddressSet: Set<String> {
        Set(sendValidation.invalidAddresses)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fromSection
                    RecipientFieldView(title: "To", addresses: $toAddresses, invalidAddresses: invalidAddressSet, querySuggestions: queryContacts)

                    if showCC {
                        RecipientFieldView(title: "CC", addresses: $ccAddresses, invalidAddresses: invalidAddressSet, querySuggestions: queryContacts)
                    }
                    if showBCC {
                        RecipientFieldView(title: "BCC", addresses: $bccAddresses, invalidAddresses: invalidAddressSet, querySuggestions: queryContacts)
                    }

                    HStack(spacing: 12) {
                        if !showCC {
                            Button("Add CC") { showCC = true }
                                .buttonStyle(.borderless)
                        }
                        if !showBCC {
                            Button("Add BCC") { showBCC = true }
                                .buttonStyle(.borderless)
                        }
                    }

                    TextField("Subject", text: $subject)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Subject")

                    BodyEditorView(
                        bodyText: $bodyText,
                        onInsertBold: { insertMarkdown("**bold**") },
                        onInsertItalic: { insertMarkdown("*italic*") },
                        onInsertLink: { insertMarkdown("[text](https://)") }
                    )

                    SmartReplyChipView(suggestions: smartReplies) { suggestion in
                        if bodyText.isEmpty {
                            bodyText = suggestion
                        } else {
                            bodyText += "\n\(suggestion)"
                        }
                    }

                    AttachmentPickerView(attachments: $attachments)

                    if ComposerBodyPolicy.shouldWarnAboutBodySize(bodyText) {
                        Label("Body exceeds 100KB", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    if sendValidation.exceedsAttachmentLimit {
                        Label("Attachments exceed 25 MB. Remove attachments to send.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    if !forwardAttachmentReadiness.canSend {
                        Label("Forward contains pending attachments. Download or remove them before send.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
            .confirmationDialog("Delete draft?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .alert(
                alertTitle,
                isPresented: Binding(
                    get: { activePrompt != nil },
                    set: { if !$0 { activePrompt = nil } }
                )
            ) {
                Button("Send") { proceedPromptQueue() }
                Button("Cancel", role: .cancel) { pendingPromptQueue.removeAll() }
            }
            .alert(
                "Couldn't send message",
                isPresented: Binding(
                    get: { sendErrorMessage != nil },
                    set: { if !$0 { sendErrorMessage = nil } }
                )
            ) {
                Button("Retry") { attemptSend() }
                Button("OK", role: .cancel) { sendErrorMessage = nil }
            } message: {
                Text(sendErrorMessage ?? "Tap retry.")
            }
            .task {
                guard !initialLoaded else { return }
                initialLoaded = true
                applyPrefill()
                loadInitialSmartReplies()
            }
        }
    }

    private var title: String {
        switch mode {
        case .new: return "New Message"
        case .reply: return "Reply"
        case .replyAll: return "Reply All"
        case .forward: return "Forward"
        }
    }

    private var alertTitle: String {
        switch activePrompt {
        case .emptySubject: return "Send without subject?"
        case .emptyBody: return "Send empty message?"
        case nil: return ""
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if hasMeaningfulContent {
                    showDiscardConfirmation = true
                } else {
                    dismiss()
                }
            }
            .keyboardShortcut(.cancelAction)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("Send") { attemptSend() }
                .disabled(!canTapSend)
                .keyboardShortcut("D", modifiers: [.command, .shift])
        }
    }

    private var fromSection: some View {
        Group {
            if let fromAccount, !fromAccount.isEmpty {
                LabeledContent("From", value: fromAccount)
                    .font(.subheadline)
            }
        }
    }

    private var hasMeaningfulContent: Bool {
        let hasRecipients = !(toAddresses + ccAddresses + bccAddresses).allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let hasSubject = !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasBody = !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !attachments.isEmpty
        return hasRecipients || hasSubject || hasBody || hasAttachments
    }

    private func applyPrefill() {
        let prefill = ComposerPrefillBuilder.build(mode: mode, selfAddresses: fromAccount.map { Set([$0]) } ?? Set())
        toAddresses = prefill.to
        ccAddresses = prefill.cc
        bccAddresses = prefill.bcc
        subject = prefill.subject
        bodyText = prefill.body
        attachments = prefill.attachments
        inReplyTo = prefill.inReplyTo
        references = prefill.references
        showCC = !ccAddresses.isEmpty
        showBCC = !bccAddresses.isEmpty
    }

    private func insertMarkdown(_ snippet: String) {
        if bodyText.isEmpty {
            bodyText = snippet
        } else {
            bodyText += "\n\(snippet)"
        }
    }

    private func attemptSend() {
        guard canTapSend else { return }
        let prompts = ComposerSendPromptPolicy.requiredPrompts(subject: subject, body: bodyText)
        if prompts.isEmpty {
            Task { await performSend() }
            return
        }

        pendingPromptQueue = prompts
        activePrompt = pendingPromptQueue.first
    }

    private func proceedPromptQueue() {
        guard !pendingPromptQueue.isEmpty else {
            activePrompt = nil
            Task { await performSend() }
            return
        }
        pendingPromptQueue.removeFirst()
        activePrompt = pendingPromptQueue.first
        if activePrompt == nil {
            Task { await performSend() }
        }
    }

    private func loadInitialSmartReplies() {
        switch mode {
        case .reply, .replyAll:
            smartReplies = Array(initialSmartReplies.prefix(3))
        case .new, .forward:
            smartReplies = []
        }
    }

    @MainActor
    private func performSend() async {
        let accountId = fromAccountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fromAddress = fromAccount?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !accountId.isEmpty, !fromAddress.isEmpty else {
            sendErrorMessage = "Missing sender account. Select an account and retry."
            return
        }

        isSending = true
        defer { isSending = false }

        let request = SendEmailRequest(
            accountId: accountId,
            fromAddress: fromAddress,
            to: normalizedAddresses(toAddresses),
            cc: normalizedAddresses(ccAddresses),
            bcc: normalizedAddresses(bccAddresses),
            subject: subject,
            bodyText: bodyText,
            inReplyTo: inReplyTo,
            references: references,
            attachments: attachments
        )

        do {
            let repository = EmailRepositoryImpl(modelContainer: modelContext.container)
            let sendUseCase = SendEmailUseCase(repository: repository)
            _ = try await sendUseCase.execute(request)
            dismiss()
        } catch {
            sendErrorMessage = error.localizedDescription.isEmpty ? "Tap retry." : error.localizedDescription
        }
    }

    private func queryContacts(_ query: String) async -> [ContactSuggestion] {
        let repository = EmailRepositoryImpl(modelContainer: modelContext.container)
        let useCase = QueryContactsUseCase(repository: repository)
        do {
            return try await useCase.execute(query: query, limit: 8)
        } catch {
            return []
        }
    }

    private func normalizedAddresses(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

#Preview("New") {
    ComposerView(mode: .new, fromAccountId: "acc-1", fromAccount: "me@example.com")
}

#Preview("Reply") {
    ComposerView(
        mode: .reply(
            ComposerSourceEmail(
                subject: "Project status",
                bodyPlain: "Looks good to me",
                fromAddress: "alice@example.com",
                fromName: "Alice",
                toAddresses: ["me@example.com"],
                ccAddresses: ["team@example.com"],
                dateSent: .now,
                messageId: "<id>",
                references: "<root>"
            )
        ),
        fromAccountId: "acc-1",
        fromAccount: "me@example.com"
    )
}
