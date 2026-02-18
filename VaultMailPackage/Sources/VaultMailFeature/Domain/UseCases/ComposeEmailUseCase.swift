import Foundation

/// Use case for email composition lifecycle: drafts, sending, and undo.
///
/// Per FR-FOUND-01, views call this use case — never repositories directly.
/// Wraps all repository errors as `ComposerError`.
///
/// Spec ref: Email Composer spec FR-COMP-01, FR-COMP-02
@MainActor
public protocol ComposeEmailUseCaseProtocol {
    /// Build pre-filled composer fields based on composition mode.
    func buildPrefill(mode: ComposerMode, userEmail: String) -> ComposerPrefill

    /// Save or update a draft email. Returns the draft email ID.
    func saveDraft(
        draftId: String?,
        accountId: String,
        threadId: String?,
        toAddresses: [String],
        ccAddresses: [String],
        bccAddresses: [String],
        subject: String,
        bodyPlain: String,
        inReplyTo: String?,
        references: String?,
        attachments: [AttachmentItem]
    ) async throws -> String

    /// Queue an email for sending (sendState → .queued, isDraft → false).
    func queueForSending(emailId: String) async throws

    /// Undo a queued send (sendState → .none, isDraft → true).
    func undoSend(emailId: String) async throws

    /// Execute the actual send after undo window expires.
    /// Transitions .queued → .sending → .sent (or .failed).
    /// Connects to SMTP, encodes MIME message, and transmits.
    func executeSend(emailId: String) async throws

    /// Delete a draft email.
    func deleteDraft(emailId: String) async throws

    /// Recover emails stuck in `.sending` state after a crash.
    /// Transitions them to `.failed` so the user can retry.
    func recoverStuckSendingEmails() async
}

/// Default implementation of `ComposeEmailUseCaseProtocol`.
///
/// Each method delegates to `EmailRepositoryProtocol` and maps errors
/// to `ComposerError`. The `executeSend` method connects to SMTP via
/// `SMTPClientProtocol` and transmits the MIME-encoded message.
///
/// Spec ref: Email Composer spec FR-COMP-01, FR-COMP-02
@MainActor
public final class ComposeEmailUseCase: ComposeEmailUseCaseProtocol {

    private let repository: EmailRepositoryProtocol
    private let accountRepository: AccountRepositoryProtocol
    private let keychainManager: KeychainManagerProtocol
    private let smtpClient: SMTPClientProtocol
    private let connectionProvider: ConnectionProviding?

    public init(
        repository: EmailRepositoryProtocol,
        accountRepository: AccountRepositoryProtocol,
        keychainManager: KeychainManagerProtocol,
        smtpClient: SMTPClientProtocol,
        connectionProvider: ConnectionProviding? = nil
    ) {
        self.repository = repository
        self.accountRepository = accountRepository
        self.keychainManager = keychainManager
        self.smtpClient = smtpClient
        self.connectionProvider = connectionProvider
    }

    // MARK: - Build Prefill

    public func buildPrefill(mode: ComposerMode, userEmail: String) -> ComposerPrefill {
        switch mode {
        case .new:
            return ComposerPrefill()

        case .reply(let ctx):
            return buildReplyPrefill(ctx: ctx, replyAll: false, userEmail: userEmail)

        case .replyAll(let ctx):
            return buildReplyPrefill(ctx: ctx, replyAll: true, userEmail: userEmail)

        case .forward(let ctx):
            return buildForwardPrefill(ctx: ctx)

        case .editDraft(let ctx):
            return buildDraftPrefill(ctx: ctx)
        }
    }

    // MARK: - Draft Lifecycle

    public func saveDraft(
        draftId: String?,
        accountId: String,
        threadId: String?,
        toAddresses: [String],
        ccAddresses: [String],
        bccAddresses: [String],
        subject: String,
        bodyPlain: String,
        inReplyTo: String?,
        references: String?,
        attachments: [AttachmentItem]
    ) async throws -> String {
        do {
            let toJSON = encodeAddresses(toAddresses)
            let ccJSON = ccAddresses.isEmpty ? nil : encodeAddresses(ccAddresses)
            let bccJSON = bccAddresses.isEmpty ? nil : encodeAddresses(bccAddresses)

            // Check if updating existing draft
            if let draftId, let existingEmail = try await repository.getEmail(id: draftId) {
                existingEmail.toAddresses = toJSON
                existingEmail.ccAddresses = ccJSON
                existingEmail.bccAddresses = bccJSON
                existingEmail.subject = subject
                existingEmail.bodyPlain = bodyPlain
                existingEmail.inReplyTo = inReplyTo
                existingEmail.references = references
                existingEmail.dateSent = Date()
                try await repository.saveEmail(existingEmail)

                // Sync attachments: remove old, add current
                try await syncAttachments(attachments, for: existingEmail)

                return draftId
            }

            // Create new draft
            let resolvedThreadId = threadId ?? UUID().uuidString
            let email = Email(
                accountId: accountId,
                threadId: resolvedThreadId,
                messageId: "<\(UUID().uuidString)@vaultmail.local>",
                inReplyTo: inReplyTo,
                references: references,
                fromAddress: "",  // Will be set from account on send
                toAddresses: toJSON,
                ccAddresses: ccJSON,
                bccAddresses: bccJSON,
                subject: subject,
                bodyPlain: bodyPlain,
                dateSent: Date(),
                isRead: true,
                isDraft: true,
                sendState: SendState.none.rawValue
            )

            // Ensure thread exists
            if try await repository.getThread(id: resolvedThreadId) == nil {
                let thread = Thread(
                    id: resolvedThreadId,
                    accountId: accountId,
                    subject: subject,
                    latestDate: Date(),
                    messageCount: 1,
                    unreadCount: 0,
                    isStarred: false
                )
                try await repository.saveThread(thread)
            }

            try await repository.saveEmail(email)

            // Save attachments
            try await syncAttachments(attachments, for: email)

            // Place in Drafts folder
            let folders = try await repository.getFolders(accountId: accountId)
            if let draftsFolder = folders.first(where: { $0.folderType == FolderType.drafts.rawValue }) {
                let emailFolder = EmailFolder(imapUID: 0)
                emailFolder.email = email
                emailFolder.folder = draftsFolder
                try await repository.saveEmailFolder(emailFolder)
            }

            return email.id

        } catch let error as ComposerError {
            throw error
        } catch {
            throw ComposerError.saveDraftFailed(error.localizedDescription)
        }
    }

    /// Syncs attachment items from the composer to the Email model.
    ///
    /// Removes attachments no longer present, adds new ones, skips unchanged.
    private func syncAttachments(_ items: [AttachmentItem], for email: Email) async throws {
        let existingIds = Set(email.attachments.map(\.id))
        let newIds = Set(items.map(\.id))

        // Remove attachments that are no longer in the composer
        let toRemove = email.attachments.filter { !newIds.contains($0.id) }
        for attachment in toRemove {
            email.attachments.removeAll { $0.id == attachment.id }
        }

        // Add new attachments
        for item in items where !existingIds.contains(item.id) {
            let attachment = Attachment(
                id: item.id,
                filename: item.filename,
                mimeType: item.mimeType,
                sizeBytes: item.sizeBytes,
                localPath: item.localPath,
                isDownloaded: item.localPath != nil
            )
            attachment.email = email
            try await repository.saveAttachment(attachment)
        }
    }

    public func queueForSending(emailId: String) async throws {
        do {
            guard let email = try await repository.getEmail(id: emailId) else {
                throw ComposerError.sendFailed("Email not found")
            }
            email.isDraft = false
            email.sendState = SendState.queued.rawValue
            email.sendQueuedDate = Date()
            try await repository.saveEmail(email)
        } catch let error as ComposerError {
            throw error
        } catch {
            throw ComposerError.sendFailed(error.localizedDescription)
        }
    }

    public func undoSend(emailId: String) async throws {
        do {
            guard let email = try await repository.getEmail(id: emailId) else {
                throw ComposerError.sendFailed("Email not found")
            }
            email.isDraft = true
            email.sendState = SendState.none.rawValue
            email.sendQueuedDate = nil
            try await repository.saveEmail(email)
        } catch let error as ComposerError {
            throw error
        } catch {
            throw ComposerError.sendFailed(error.localizedDescription)
        }
    }

    public func executeSend(emailId: String) async throws {
        do {
            guard let email = try await repository.getEmail(id: emailId) else {
                throw ComposerError.sendFailed("Email not found")
            }

            // Transition to sending
            email.sendState = SendState.sending.rawValue
            try await repository.saveEmail(email)

            // Look up the account to get SMTP settings and email
            let accounts = try await accountRepository.getAccounts()
            guard let account = accounts.first(where: { $0.id == email.accountId }) else {
                email.sendState = SendState.failed.rawValue
                try await repository.saveEmail(email)
                throw ComposerError.sendFailed("Account not found for email")
            }

            // Resolve both IMAP and SMTP credentials via shared CredentialResolver
            let credResolver = CredentialResolver(
                keychainManager: keychainManager,
                accountRepository: accountRepository
            )
            let resolvedSmtpCredential: SMTPCredential
            let resolvedImapCredential: IMAPCredential
            do {
                let creds = try await credResolver.resolveBothCredentials(for: account, refreshIfNeeded: true)
                resolvedSmtpCredential = creds.smtp
                resolvedImapCredential = creds.imap
            } catch {
                email.sendState = SendState.failed.rawValue
                try await repository.saveEmail(email)
                throw ComposerError.sendFailed("Credential resolution failed: \(error.localizedDescription)")
            }

            // Decode recipient addresses
            let toAddresses = decodeAddresses(email.toAddresses)
            let ccAddresses = decodeAddresses(email.ccAddresses ?? "[]")
            let bccAddresses = decodeAddresses(email.bccAddresses ?? "[]")
            let allRecipients = toAddresses + ccAddresses + bccAddresses

            guard !allRecipients.isEmpty else {
                email.sendState = SendState.failed.rawValue
                try await repository.saveEmail(email)
                throw ComposerError.sendFailed("No recipients specified")
            }

            // Set from address on the email
            email.fromAddress = account.email
            email.fromName = account.displayName.isEmpty ? nil : account.displayName

            // Snapshot values needed for off-main-actor work so we
            // don't access SwiftData objects from a non-isolated context.
            struct AttachmentRef: Sendable {
                let filename: String
                let mimeType: String
                let localPath: String?
            }
            let attachmentRefs = email.attachments.map {
                AttachmentRef(filename: $0.filename, mimeType: $0.mimeType, localPath: $0.localPath)
            }
            let fromEmail = account.email
            let fromName = account.displayName.isEmpty ? nil : account.displayName
            let subjectText = email.subject
            let bodyPlainText = email.bodyPlain ?? ""
            let bodyHTMLText = email.bodyHTML
            let messageIdText = email.messageId
            let inReplyToText = email.inReplyTo
            let referencesText = email.references
            let sendDate = Date()

            // Move file I/O and MIME encoding off the main actor to
            // avoid blocking the UI thread (review comment #4).
            let messageData: Data
            do {
                messageData = try await Task.detached(priority: .userInitiated) {
                    // Load attachment data from local files
                    var attachmentDataList: [MIMEEncoder.AttachmentData] = []
                    for ref in attachmentRefs {
                        guard let localPath = ref.localPath else { continue }
                        let fileURL = URL(fileURLWithPath: localPath)
                        guard let fileData = try? Data(contentsOf: fileURL) else {
                            throw ComposerError.sendFailed(
                                "Could not read attachment \"\(ref.filename)\". Please re-add it and try again."
                            )
                        }
                        attachmentDataList.append(MIMEEncoder.AttachmentData(
                            filename: ref.filename,
                            mimeType: ref.mimeType,
                            data: fileData
                        ))
                    }

                    // Build MIME message
                    return MIMEEncoder.encode(
                        from: fromEmail,
                        fromName: fromName,
                        toAddresses: toAddresses,
                        ccAddresses: ccAddresses,
                        bccAddresses: bccAddresses,
                        subject: subjectText,
                        bodyPlain: bodyPlainText,
                        bodyHTML: bodyHTMLText,
                        messageId: messageIdText,
                        inReplyTo: inReplyToText,
                        references: referencesText,
                        date: sendDate,
                        attachments: attachmentDataList
                    )
                }.value
            } catch {
                email.sendState = SendState.failed.rawValue
                try await repository.saveEmail(email)
                throw error
            }

            // Use pre-resolved SMTP credential
            let smtpCredential = resolvedSmtpCredential

            // Connect to SMTP and send
            NSLog("[ComposeSend] Connecting SMTP: \(account.smtpHost):\(account.smtpPort) security=\(account.resolvedSmtpSecurity.rawValue)")
            do {
                try await smtpClient.connect(
                    host: account.smtpHost,
                    port: account.smtpPort,
                    security: account.resolvedSmtpSecurity,
                    credential: smtpCredential
                )
                NSLog("[ComposeSend] SMTP connected, sending to \(allRecipients)")

                try await smtpClient.sendMessage(
                    from: account.email,
                    recipients: allRecipients,
                    messageData: messageData
                )
                NSLog("[ComposeSend] SMTP send succeeded")

                await smtpClient.disconnect()
            } catch {
                NSLog("[ComposeSend] SMTP send FAILED: \(error)")
                await smtpClient.disconnect()

                // Retry logic
                email.sendRetryCount += 1
                if email.sendRetryCount >= AppConstants.maxSendRetryCount {
                    email.sendState = SendState.failed.rawValue
                    try await repository.saveEmail(email)
                    throw ComposerError.sendFailed("Send failed after \(AppConstants.maxSendRetryCount) retries: \(error.localizedDescription)")
                } else {
                    // Re-queue for retry
                    email.sendState = SendState.queued.rawValue
                    try await repository.saveEmail(email)
                    throw ComposerError.sendFailed("Send failed, will retry: \(error.localizedDescription)")
                }
            }

            // Transition to sent
            email.sendState = SendState.sent.rawValue
            email.dateSent = Date()
            try await repository.saveEmail(email)
            NSLog("[ComposeSend] Email marked as sent: \(email.id)")

            // Move from Drafts to Sent folder
            let accountId = email.accountId
            let folders = try await repository.getFolders(accountId: accountId)
            NSLog("[ComposeSend] Found \(folders.count) folders for account \(accountId)")
            for f in folders {
                NSLog("[ComposeSend]   folder: \(f.name) type=\(f.folderType) id=\(f.id)")
            }

            // Remove from Drafts folder
            let draftsType = FolderType.drafts.rawValue
            let draftsEFs = email.emailFolders.filter { $0.folder?.folderType == draftsType }
            NSLog("[ComposeSend] Removing \(draftsEFs.count) Drafts folder associations")
            for ef in draftsEFs {
                email.emailFolders.removeAll { $0.id == ef.id }
            }

            // Add to Sent folder
            if let sentFolder = folders.first(where: { $0.folderType == FolderType.sent.rawValue }) {
                let alreadyInSent = email.emailFolders.contains { $0.folder?.id == sentFolder.id }
                NSLog("[ComposeSend] Sent folder found: \(sentFolder.name) (id=\(sentFolder.id)), alreadyInSent=\(alreadyInSent)")
                if !alreadyInSent {
                    let sentEF = EmailFolder(imapUID: 0)
                    sentEF.email = email
                    sentEF.folder = sentFolder
                    try await repository.saveEmailFolder(sentEF)
                    NSLog("[ComposeSend] Email added to Sent folder")
                }
            } else {
                NSLog("[ComposeSend] WARNING: No Sent folder found for account \(accountId)")
            }

            // Ensure email.thread relationship is set (needed for thread-based queries)
            if email.thread == nil, let thread = try await repository.getThread(id: email.threadId) {
                email.thread = thread
                NSLog("[ComposeSend] Linked email to thread \(thread.id)")
            }

            // IMAP APPEND to Sent folder if required by provider (FR-MPROV-12).
            // Gmail auto-copies sent messages; Yahoo/iCloud/Outlook need explicit APPEND.
            let providerConfig = ProviderRegistry.provider(for: account.resolvedProvider)
            NSLog("[ComposeSend] Provider=\(account.resolvedProvider.rawValue), requiresSentAppend=\(providerConfig?.requiresSentAppend ?? true), hasConnectionProvider=\(connectionProvider != nil)")
            if providerConfig?.requiresSentAppend ?? true,
               let provider = connectionProvider {
                await appendToSentFolder(
                    account: account,
                    messageData: messageData,
                    imapCredential: resolvedImapCredential,
                    connectionProvider: provider
                )
            }

            // Update thread metadata (participants, snippet, latestDate)
            let thread: VaultMailFeature.Thread?
            if let t = email.thread {
                thread = t
            } else if let t = try await repository.getThread(id: email.threadId) {
                email.thread = t
                thread = t
            } else {
                thread = nil
            }

            if let thread {
                thread.latestDate = email.dateSent
                thread.snippet = String(email.bodyPlain?.prefix(100) ?? "")
                thread.subject = email.subject

                // Build participants from recipients (for Sent folder display)
                var participantSet: [String: Participant] = [:]
                // Add sender (self)
                if !email.fromAddress.isEmpty {
                    participantSet[email.fromAddress.lowercased()] = Participant(
                        name: email.fromName,
                        email: email.fromAddress
                    )
                }
                // Add To recipients
                for addr in decodeAddresses(email.toAddresses) {
                    let key = addr.lowercased()
                    if participantSet[key] == nil {
                        participantSet[key] = Participant(name: nil, email: addr)
                    }
                }
                thread.participants = Participant.encode(Array(participantSet.values))

                try await repository.saveThread(thread)
                NSLog("[ComposeSend] Thread \(thread.id) updated with participants and latestDate")
            } else {
                NSLog("[ComposeSend] WARNING: no thread found for email \(email.id)")
            }

        } catch let error as ComposerError {
            throw error
        } catch {
            throw ComposerError.sendFailed(error.localizedDescription)
        }
    }

    public func deleteDraft(emailId: String) async throws {
        do {
            try await repository.deleteEmail(id: emailId)
        } catch {
            throw ComposerError.deleteDraftFailed(error.localizedDescription)
        }
    }

    /// Recovers emails orphaned in `.sending` state (e.g., after a crash).
    ///
    /// On app launch, any email still marked `.sending` never completed its
    /// SMTP transaction — transition them to `.failed` so the user can retry
    /// or discard.
    public func recoverStuckSendingEmails() async {
        do {
            let stuck = try await repository.getEmailsBySendState(SendState.sending.rawValue)
            for email in stuck {
                email.sendState = SendState.failed.rawValue
                try await repository.saveEmail(email)
                NSLog("[ComposeEmail] Recovered stuck email \(email.id) from .sending → .failed")
            }
        } catch {
            NSLog("[ComposeEmail] Failed to recover stuck emails: \(error)")
        }
    }

    // MARK: - Provider-Aware Helpers

    /// Appends sent message to the Sent folder via IMAP (for providers that need it).
    ///
    /// Gmail auto-copies sent messages, so this is a no-op for Gmail.
    /// Yahoo, iCloud, Outlook, and custom providers need this explicit APPEND.
    /// Errors are logged but not thrown (best-effort, like thread actions).
    private func appendToSentFolder(
        account: Account,
        messageData: Data,
        imapCredential: IMAPCredential,
        connectionProvider: ConnectionProviding
    ) async {
        var client: IMAPClientProtocol?
        do {
            client = try await connectionProvider.checkoutConnection(
                accountId: account.id,
                host: account.imapHost,
                port: account.imapPort,
                security: account.resolvedImapSecurity,
                credential: imapCredential
            )

            // Find the Sent folder's IMAP path
            let folders = try await client!.listFolders()
            let provider = account.resolvedProvider
            let sentPath = folders.first { folder in
                let type = ProviderFolderMapper.folderType(
                    imapPath: folder.imapPath,
                    attributes: folder.attributes,
                    provider: provider
                )
                return type == .sent
            }?.imapPath

            guard let sentPath else {
                NSLog("[ComposeSend] No Sent folder found for IMAP APPEND — skipping")
                await connectionProvider.checkinConnection(client!, accountId: account.id)
                return
            }

            try await client!.appendMessage(
                to: sentPath,
                messageData: messageData,
                flags: ["\\Seen"]
            )
            NSLog("[ComposeSend] IMAP APPEND to \(sentPath) succeeded")
            await connectionProvider.checkinConnection(client!, accountId: account.id)
        } catch {
            NSLog("[ComposeSend] IMAP APPEND to Sent failed (best-effort): \(error)")
            if let client {
                await connectionProvider.checkinConnection(client, accountId: account.id)
            }
        }
    }

    // MARK: - Private Helpers

    private func buildReplyPrefill(ctx: ComposerEmailContext, replyAll: Bool, userEmail: String) -> ComposerPrefill {
        // To: original sender
        var toAddresses = [ctx.fromAddress]

        var ccAddresses: [String] = []

        if replyAll {
            // Add original To recipients (minus self)
            let originalTo = decodeAddresses(ctx.toAddresses)
            let filteredTo = originalTo.filter { $0.lowercased() != userEmail.lowercased() }
            toAddresses.append(contentsOf: filteredTo)

            // Add original CC recipients (minus self)
            if let ccJSON = ctx.ccAddresses {
                let originalCC = decodeAddresses(ccJSON)
                ccAddresses = originalCC.filter { $0.lowercased() != userEmail.lowercased() }
            }

            // Remove self from To as well
            toAddresses = toAddresses.filter { $0.lowercased() != userEmail.lowercased() }
            if toAddresses.isEmpty {
                toAddresses = [ctx.fromAddress] // At minimum, reply to sender
            }
        }

        // Subject: add "Re: " prefix with deduplication
        let subject = addSubjectPrefix("Re: ", to: ctx.subject)

        // References: append original messageId to chain
        var refs = ctx.references ?? ""
        if !refs.isEmpty { refs += " " }
        refs += ctx.messageId

        // Quoted body
        let dateStr = formatDateForQuote(ctx.dateSent)
        let senderName = ctx.fromName ?? ctx.fromAddress
        let quotedBody = buildQuotedBody(
            header: "On \(dateStr), \(senderName) wrote:",
            originalBody: ctx.bodyPlain ?? ""
        )

        return ComposerPrefill(
            toAddresses: toAddresses,
            ccAddresses: ccAddresses,
            subject: subject,
            bodyPrefix: quotedBody,
            inReplyTo: ctx.messageId,
            references: refs
        )
    }

    private func buildForwardPrefill(ctx: ComposerEmailContext) -> ComposerPrefill {
        let subject = addSubjectPrefix("Fwd: ", to: ctx.subject)

        let dateStr = formatDateForQuote(ctx.dateSent)
        let toStr = decodeAddresses(ctx.toAddresses).joined(separator: ", ")

        var forwardHeader = "\n\n---------- Forwarded message ----------\n"
        forwardHeader += "From: \(ctx.fromAddress)\n"
        forwardHeader += "Date: \(dateStr)\n"
        forwardHeader += "Subject: \(ctx.subject)\n"
        forwardHeader += "To: \(toStr)\n\n"
        forwardHeader += ctx.bodyPlain ?? ""

        return ComposerPrefill(
            subject: subject,
            bodyPrefix: forwardHeader,
            forwardedAttachmentIds: ctx.attachmentIds
        )
    }

    private func buildDraftPrefill(ctx: ComposerEmailContext) -> ComposerPrefill {
        return ComposerPrefill(
            toAddresses: decodeAddresses(ctx.toAddresses),
            ccAddresses: decodeAddresses(ctx.ccAddresses ?? "[]"),
            bccAddresses: decodeAddresses(ctx.bccAddresses ?? "[]"),
            subject: ctx.subject,
            bodyPrefix: ctx.bodyPlain ?? "",
            inReplyTo: ctx.inReplyTo,
            references: ctx.references,
            forwardedAttachmentIds: ctx.attachmentIds
        )
    }

    /// Add a prefix ("Re: " or "Fwd: ") with deduplication.
    /// Prevents "Re: Re: Re: Subject" — only one prefix is applied.
    private func addSubjectPrefix(_ prefix: String, to subject: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        // Check if already has this prefix (case-insensitive)
        if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
            return trimmed
        }
        // Also handle mixed prefixes: "Fwd: Re: Fwd:" etc. — just prepend once
        return prefix + trimmed
    }

    private func buildQuotedBody(header: String, originalBody: String) -> String {
        let quotedLines = originalBody
            .components(separatedBy: .newlines)
            .map { "> \($0)" }
            .joined(separator: "\n")
        return "\n\n\(header)\n\(quotedLines)"
    }

    private func formatDateForQuote(_ date: Date?) -> String {
        guard let date else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func encodeAddresses(_ addresses: [String]) -> String {
        guard let data = try? JSONEncoder().encode(addresses),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func decodeAddresses(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let addresses = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return addresses
    }
}
