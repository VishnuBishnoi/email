import Foundation

/// Production IMAP client conforming to `IMAPClientProtocol`.
///
/// Uses `IMAPSession` for TLS connection management and `IMAPResponseParser`
/// for parsing IMAP server responses into domain DTOs.
///
/// Architecture (AI-01): Data layer implementation of Domain protocol.
/// Spec ref: FR-SYNC-01, FR-SYNC-03, FR-SYNC-09
/// Validation ref: AC-F-05
public actor IMAPClient: IMAPClientProtocol {

    // MARK: - Properties

    private let session: IMAPSession
    private var _isConnected = false
    private var _selectedFolder: String?
    private var idleTask: Task<Void, Never>?
    private var idleHandler: (@Sendable () -> Void)?

    // MARK: - Init

    /// Creates an IMAP client with the specified timeout.
    ///
    /// - Parameter timeout: Connection timeout in seconds (FR-SYNC-09: 30s default)
    public init(timeout: TimeInterval = AppConstants.imapConnectionTimeout) {
        self.session = IMAPSession(timeout: timeout)
    }

    // MARK: - IMAPClientProtocol: Connection

    public var isConnected: Bool {
        _isConnected
    }

    /// Connects to the IMAP server using TLS and authenticates with XOAUTH2.
    ///
    /// Per AC-F-05:
    /// - Connection MUST use TLS (port 993)
    /// - XOAUTH2 authentication MUST succeed with valid credentials
    ///
    /// Per FR-SYNC-09:
    /// - Connection timeout: 30 seconds
    /// - Retry with exponential backoff: 5s, 15s, 45s
    public func connect(host: String, port: Int, email: String, accessToken: String) async throws {
        var lastError: Error?

        // Retry logic per FR-SYNC-09: 3 retries with exponential backoff (5s, 15s, 45s)
        for attempt in 0...AppConstants.imapMaxRetries {
            do {
                try await session.connect(host: host, port: port)
                try await session.authenticateXOAUTH2(email: email, accessToken: accessToken)
                _isConnected = true
                return
            } catch let error as IMAPError {
                lastError = error

                // Don't retry auth failures — they won't resolve with retries
                if case .authenticationFailed = error {
                    throw error
                }

                // Don't retry on the last attempt
                if attempt < AppConstants.imapMaxRetries {
                    let delay = AppConstants.imapRetryBaseDelay * pow(3.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    // Disconnect before retrying
                    await session.disconnect()
                }
            } catch {
                lastError = error
                if attempt < AppConstants.imapMaxRetries {
                    let delay = AppConstants.imapRetryBaseDelay * pow(3.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    await session.disconnect()
                }
            }
        }

        throw lastError ?? IMAPError.maxRetriesExhausted
    }

    /// Disconnects from the IMAP server gracefully.
    public func disconnect() async throws {
        idleTask?.cancel()
        idleTask = nil
        idleHandler = nil

        await session.disconnect()
        _isConnected = false
        _selectedFolder = nil
    }

    // MARK: - IMAPClientProtocol: Folder Operations

    /// Lists all available IMAP folders with their attributes.
    ///
    /// Maps to IMAP `LIST "" "*"` command.
    /// Per AC-F-05: MUST list all Gmail folders (INBOX, Sent, Drafts, Trash, Spam,
    /// All Mail, Starred, plus user labels).
    public func listFolders() async throws -> [IMAPFolderInfo] {
        let responses = try await session.execute("LIST \"\" \"*\"")
        return responses.compactMap { IMAPResponseParser.parseListResponse($0) }
    }

    /// Selects a folder for subsequent operations.
    ///
    /// Returns UIDVALIDITY and EXISTS count from the server's SELECT response.
    public func selectFolder(_ imapPath: String) async throws -> (uidValidity: UInt32, messageCount: UInt32) {
        let responses = try await session.execute("SELECT \"\(imapPath)\"")

        let uidValidity = IMAPResponseParser.parseUIDValidity(from: responses)
        let messageCount = IMAPResponseParser.parseExists(from: responses)

        if uidValidity == 0 && messageCount == 0 {
            // Check if the server returned an error for the folder
            let responseText = responses.joined(separator: " ")
            if responseText.contains("[NONEXISTENT]") || responseText.contains("not found") {
                throw IMAPError.folderNotFound(imapPath)
            }
        }

        _selectedFolder = imapPath
        return (uidValidity: uidValidity, messageCount: messageCount)
    }

    // MARK: - IMAPClientProtocol: Search & Fetch

    /// Searches for message UIDs since a given date in the selected folder.
    ///
    /// Maps to IMAP `UID SEARCH SINCE <date>`.
    /// Per AC-F-05: MUST fetch email UIDs within a date range.
    public func searchUIDs(since date: Date) async throws -> [UInt32] {
        let formatter = DateFormatter()
        formatter.dateFormat = "d-MMM-yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dateStr = formatter.string(from: date)

        let responses = try await session.execute("UID SEARCH SINCE \(dateStr)")
        return IMAPResponseParser.parseSearchResponse(from: responses)
    }

    /// Fetches email headers for specified UIDs.
    ///
    /// Uses `BODY.PEEK[HEADER.FIELDS (...)]` to fetch specific headers without
    /// marking messages as read (PEEK).
    ///
    /// Per AC-F-05: MUST fetch complete email headers
    /// (From, To, CC, Subject, Date, Message-ID, References, In-Reply-To).
    public func fetchHeaders(uids: [UInt32]) async throws -> [IMAPEmailHeader] {
        guard !uids.isEmpty else { return [] }

        let uidSet = uids.map(String.init).joined(separator: ",")
        let headerFields = "FROM TO CC BCC SUBJECT DATE MESSAGE-ID IN-REPLY-TO REFERENCES"
        let command = "UID FETCH \(uidSet) (UID FLAGS RFC822.SIZE BODY.PEEK[HEADER.FIELDS (\(headerFields))])"

        let responses = try await session.execute(command)
        return IMAPResponseParser.parseHeaderResponses(responses)
    }

    /// Fetches email bodies for specified UIDs.
    ///
    /// Two-step process:
    /// 1. Fetch BODYSTRUCTURE to determine text/plain and text/html part IDs
    /// 2. Fetch those specific parts using BODY.PEEK[<partId>]
    ///
    /// Per AC-F-05: MUST fetch email bodies (plain text and HTML parts).
    /// Per FR-SYNC-08: MUST extract attachment metadata from BODYSTRUCTURE.
    public func fetchBodies(uids: [UInt32]) async throws -> [IMAPEmailBody] {
        guard !uids.isEmpty else { return [] }

        var bodies: [IMAPEmailBody] = []

        for uid in uids {
            // Step 1: Fetch BODYSTRUCTURE
            let bsCommand = "UID FETCH \(uid) (UID BODYSTRUCTURE)"
            let bsResponses = try await session.execute(bsCommand)
            let bsResponse = bsResponses.joined(separator: "\n")

            let bodyParts = IMAPResponseParser.parseBodyStructure(from: bsResponse)
            let attachments = bodyParts
                .filter { $0.isAttachment }
                .map { part in
                    IMAPAttachmentInfo(
                        partId: part.partId,
                        filename: part.filename,
                        mimeType: part.mimeType,
                        sizeBytes: part.size,
                        contentId: part.contentId
                    )
                }

            // Step 2: Find text parts to fetch
            let textParts = bodyParts.filter { !$0.isAttachment }
            var plainText: String?
            var htmlText: String?

            if textParts.isEmpty {
                // Simple message — fetch BODY[TEXT]
                let bodyCommand = "UID FETCH \(uid) (UID BODY.PEEK[TEXT])"
                let bodyResponses = try await session.execute(bodyCommand)
                let bodyResponse = bodyResponses.joined(separator: "\n")

                // Extract the literal content
                if let literalStart = bodyResponse.firstIndex(of: "\n") {
                    plainText = String(bodyResponse[bodyResponse.index(after: literalStart)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                // Fetch specific text parts
                for part in textParts {
                    let fetchCmd = "UID FETCH \(uid) (UID BODY.PEEK[\(part.partId)])"
                    let fetchResponses = try await session.execute(fetchCmd)
                    let fetchResponse = fetchResponses.joined(separator: "\n")

                    // Extract literal content
                    if let literalStart = fetchResponse.firstIndex(of: "\n") {
                        let content = String(fetchResponse[fetchResponse.index(after: literalStart)...])
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        if part.mimeType.contains("html") {
                            htmlText = content
                        } else {
                            plainText = content
                        }
                    }
                }
            }

            bodies.append(IMAPEmailBody(
                uid: uid,
                plainText: plainText,
                htmlText: htmlText,
                attachments: attachments
            ))
        }

        return bodies
    }

    /// Fetches current flags for specified UIDs.
    ///
    /// Per FR-SYNC-10: Server → Local flag pull.
    public func fetchFlags(uids: [UInt32]) async throws -> [UInt32: [String]] {
        guard !uids.isEmpty else { return [:] }

        let uidSet = uids.map(String.init).joined(separator: ",")
        let responses = try await session.execute("UID FETCH \(uidSet) (UID FLAGS)")
        return IMAPResponseParser.parseFlagResponses(responses)
    }

    // MARK: - IMAPClientProtocol: Flag Operations

    /// Stores (adds/removes) flags on a message.
    ///
    /// Per FR-SYNC-10:
    /// - Mark read: add \\Seen
    /// - Mark unread: remove \\Seen
    /// - Star: add \\Flagged
    /// - Unstar: remove \\Flagged
    public func storeFlags(uid: UInt32, add: [String], remove: [String]) async throws {
        if !add.isEmpty {
            let flagStr = add.joined(separator: " ")
            _ = try await session.execute("UID STORE \(uid) +FLAGS (\(flagStr))")
        }

        if !remove.isEmpty {
            let flagStr = remove.joined(separator: " ")
            _ = try await session.execute("UID STORE \(uid) -FLAGS (\(flagStr))")
        }
    }

    // MARK: - IMAPClientProtocol: Copy & Delete

    /// Copies messages to another folder.
    ///
    /// Per FR-SYNC-10: Archive = COPY to All Mail.
    public func copyMessages(uids: [UInt32], to destinationPath: String) async throws {
        guard !uids.isEmpty else { return }

        let uidSet = uids.map(String.init).joined(separator: ",")
        _ = try await session.execute("UID COPY \(uidSet) \"\(destinationPath)\"")
    }

    /// Permanently removes messages from the currently selected folder.
    ///
    /// Sets \\Deleted flag and issues EXPUNGE.
    /// Per FR-SYNC-10: Archive = COPY + DELETE + EXPUNGE.
    public func expungeMessages(uids: [UInt32]) async throws {
        guard !uids.isEmpty else { return }

        // Mark messages as deleted
        for uid in uids {
            _ = try await session.execute("UID STORE \(uid) +FLAGS (\\Deleted)")
        }

        // Expunge
        _ = try await session.execute("EXPUNGE")
    }

    // MARK: - IMAPClientProtocol: Append

    /// Appends a raw MIME message to a folder.
    ///
    /// Used to copy sent messages to the Sent folder (FR-SYNC-07).
    public func appendMessage(to imapPath: String, messageData: Data, flags: [String]) async throws {
        try await session.executeAPPEND(folder: imapPath, flags: flags, data: messageData)
    }

    // MARK: - IMAPClientProtocol: IDLE

    /// Starts IMAP IDLE on the currently selected folder.
    ///
    /// The handler is called when the server sends an EXISTS notification.
    /// IDLE is re-issued every 25 minutes (Gmail drops after ~29 min, FR-SYNC-03).
    ///
    /// Per AC-F-05: MUST support IMAP IDLE and receive notifications
    /// within 30 seconds of new email arrival.
    public func startIDLE(onNewMail: @Sendable @escaping () -> Void) async throws {
        idleHandler = onNewMail

        _ = try await session.startIDLE()

        // Start monitoring for IDLE notifications
        idleTask = Task { [weak self] in
            guard let self else { return }
            await self.runIDLELoop()
        }
    }

    /// Stops IMAP IDLE.
    public func stopIDLE() async throws {
        idleTask?.cancel()
        idleTask = nil
        idleHandler = nil

        try await session.stopIDLE()
    }

    // MARK: - Private: IDLE Loop

    /// Runs the IDLE notification loop.
    ///
    /// Reads notifications from the server during IDLE and calls the
    /// handler on EXISTS. Re-issues IDLE every 25 minutes (FR-SYNC-03).
    private func runIDLELoop() async {
        let refreshInterval = AppConstants.imapIdleRefreshInterval
        var lastIDLEStart = Date()

        while !Task.isCancelled {
            do {
                // Check if we need to re-issue IDLE (25-minute refresh)
                if Date().timeIntervalSince(lastIDLEStart) >= refreshInterval {
                    try await session.stopIDLE()
                    _ = try await session.startIDLE()
                    lastIDLEStart = Date()
                    continue
                }

                let notification = try await session.readIDLENotification()

                // Check for new mail notification: "* <N> EXISTS"
                if notification.contains("EXISTS") {
                    idleHandler?()
                }
            } catch {
                // Connection dropped or IDLE stopped — exit loop
                break
            }
        }
    }
}
