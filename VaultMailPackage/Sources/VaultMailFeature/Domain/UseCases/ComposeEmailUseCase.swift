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

    public init(
        repository: EmailRepositoryProtocol,
        accountRepository: AccountRepositoryProtocol,
        keychainManager: KeychainManagerProtocol,
        smtpClient: SMTPClientProtocol
    ) {
        self.repository = repository
        self.accountRepository = accountRepository
        self.keychainManager = keychainManager
        self.smtpClient = smtpClient
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

            // Get OAuth access token from Keychain
            guard let token = try await keychainManager.retrieve(for: account.id) else {
                email.sendState = SendState.failed.rawValue
                try await repository.saveEmail(email)
                throw ComposerError.sendFailed("No OAuth token found. Please re-authenticate.")
            }

            let accessToken: String
            if token.isExpired || token.isNearExpiry {
                // Try to refresh the token
                do {
                    let refreshed = try await accountRepository.refreshToken(for: account.id)
                    accessToken = refreshed.accessToken
                } catch {
                    email.sendState = SendState.failed.rawValue
                    try await repository.saveEmail(email)
                    throw ComposerError.sendFailed("Token refresh failed: \(error.localizedDescription)")
                }
            } else {
                accessToken = token.accessToken
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

            // Connect to SMTP and send
            do {
                try await smtpClient.connect(
                    host: account.smtpHost,
                    port: account.smtpPort,
                    email: account.email,
                    accessToken: accessToken
                )

                try await smtpClient.sendMessage(
                    from: account.email,
                    recipients: allRecipients,
                    messageData: messageData
                )

                await smtpClient.disconnect()
            } catch {
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

            // Move from Drafts to Sent folder
            let accountId = email.accountId
            let folders = try await repository.getFolders(accountId: accountId)

            // Remove from Drafts folder
            let draftsType = FolderType.drafts.rawValue
            let draftsEFs = email.emailFolders.filter { $0.folder?.folderType == draftsType }
            for ef in draftsEFs {
                email.emailFolders.removeAll { $0.id == ef.id }
            }

            // Add to Sent folder
            if let sentFolder = folders.first(where: { $0.folderType == FolderType.sent.rawValue }) {
                let alreadyInSent = email.emailFolders.contains { $0.folder?.id == sentFolder.id }
                if !alreadyInSent {
                    let sentEF = EmailFolder(imapUID: 0)
                    sentEF.email = email
                    sentEF.folder = sentFolder
                    try await repository.saveEmailFolder(sentEF)
                }
            }

            // Update thread
            if let thread = email.thread {
                thread.latestDate = email.dateSent
                try await repository.saveThread(thread)
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
