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

    // MARK: - Shared DateFormatters (allocated once, reused)

    /// IMAP SEARCH date format: "1-Jan-2024"
    private static let searchDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d-MMM-yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

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
        let sanitizedPath = imapPath.imapQuoteSanitized
        let responses = try await session.execute("SELECT \"\(sanitizedPath)\"")

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
        let dateStr = Self.searchDateFormatter.string(from: date)

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
        let headerFields = "FROM TO CC BCC SUBJECT DATE MESSAGE-ID IN-REPLY-TO REFERENCES AUTHENTICATION-RESULTS"
        let command = "UID FETCH \(uidSet) (UID FLAGS RFC822.SIZE BODY.PEEK[HEADER.FIELDS (\(headerFields))])"

        let responses = try await session.execute(command)
        return IMAPResponseParser.parseHeaderResponses(responses)
    }

    /// Fetches email bodies for specified UIDs using 2-phase batched fetch.
    ///
    /// **Phase 1**: Batch all BODYSTRUCTURE fetches in one round trip.
    /// **Phase 2**: Group UIDs by text part structure, batch body fetches per group.
    ///
    /// This eliminates the N+1 problem where the old implementation issued
    /// 2-3 IMAP commands per UID (BODYSTRUCTURE + body parts). For 100 emails,
    /// that was 200-300 round trips. Now it's 2-4 total regardless of count.
    ///
    /// Per AC-F-05: MUST fetch email bodies (plain text and HTML parts).
    /// Per FR-SYNC-08: MUST extract attachment metadata from BODYSTRUCTURE.
    /// Per NFR-SYNC-02: Initial sync < 60s for 1,000 emails.
    public func fetchBodies(uids: [UInt32]) async throws -> [IMAPEmailBody] {
        guard !uids.isEmpty else { return [] }

        // ── Phase 1: Batch BODYSTRUCTURE (1 round trip instead of N) ──
        let uidSet = uids.map(String.init).joined(separator: ",")
        let bsResponses = try await session.execute(
            "UID FETCH \(uidSet) (UID BODYSTRUCTURE)"
        )
        let structuresByUID = IMAPResponseParser.parseMultiBodyStructures(from: bsResponses)

        // Categorize each UID's text parts and collect attachment info
        var textInfoByUID: [UInt32: [(partId: String, mimeType: String, encoding: String, charset: String)]] = [:]
        var attachmentsByUID: [UInt32: [IMAPAttachmentInfo]] = [:]

        for uid in uids {
            let allParts = structuresByUID[uid] ?? []

            attachmentsByUID[uid] = allParts
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

            let textParts = allParts.filter { !$0.isAttachment }
            if textParts.isEmpty {
                // Simple message — will fetch BODY[TEXT]
                textInfoByUID[uid] = [("TEXT", "text/plain", "7BIT", "UTF-8")]
            } else {
                textInfoByUID[uid] = textParts.map { ($0.partId, $0.mimeType, $0.encoding, $0.charset) }
            }
        }

        // Group UIDs that need the same set of part IDs → one fetch per group
        // Key: sorted comma-joined part IDs, e.g. "1,2" or "TEXT"
        var groups: [String: [UInt32]] = [:]
        for uid in uids {
            let key = (textInfoByUID[uid] ?? [])
                .map { $0.partId }
                .sorted()
                .joined(separator: ",")
            groups[key, default: []].append(uid)
        }

        // ── Phase 2: Batch body fetches per group (few round trips vs N) ──
        var resultsByUID: [UInt32: (plain: String?, html: String?)] = [:]

        for (groupKey, groupUIDs) in groups {
            let groupSet = groupUIDs.map(String.init).joined(separator: ",")
            let partIds = groupKey.split(separator: ",").map(String.init)
            let peeks = partIds.map { "BODY.PEEK[\($0)]" }.joined(separator: " ")

            let responses = try await session.execute(
                "UID FETCH \(groupSet) (UID \(peeks))"
            )

            for response in responses {
                guard response.contains("FETCH") else { continue }
                let uid = IMAPResponseParser.extractUID(from: response)
                guard uid > 0 else { continue }

                let sectionContent = IMAPResponseParser.extractBodyPartsBySection(
                    from: response
                )

                var plain: String?
                var html: String?

                // Map section content to plain/html using BODYSTRUCTURE metadata,
                // applying Content-Transfer-Encoding decoding (base64, QP, etc.)
                for (partId, mimeType, encoding, charset) in textInfoByUID[uid] ?? [] {
                    guard let rawContent = sectionContent[partId] else { continue }
                    let decoded = MIMEDecoder.decodeBody(rawContent, encoding: encoding, charset: charset)

                    // When BODYSTRUCTURE returned no text parts and we fell back
                    // to BODY[TEXT], multipart messages return raw MIME content
                    // with boundaries, headers, and transfer-encoded parts.
                    // Detect and parse this to extract actual email content.
                    if partId == "TEXT" && MIMEDecoder.isMultipartContent(decoded) {
                        if let multipart = MIMEDecoder.parseMultipartBody(decoded) {
                            plain = multipart.plainText
                            html = multipart.htmlText
                            continue
                        }
                    }

                    if mimeType.contains("html") {
                        html = decoded
                    } else {
                        plain = decoded
                    }
                }

                resultsByUID[uid] = (plain, html)
            }
        }

        // Build final results preserving input UID order
        return uids.map { uid in
            let (plain, html) = resultsByUID[uid] ?? (nil, nil)
            return IMAPEmailBody(
                uid: uid,
                plainText: plain,
                htmlText: html,
                attachments: attachmentsByUID[uid] ?? []
            )
        }
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
            let flagStr = add.map { $0.imapCRLFStripped }.joined(separator: " ")
            _ = try await session.execute("UID STORE \(uid) +FLAGS (\(flagStr))")
        }

        if !remove.isEmpty {
            let flagStr = remove.map { $0.imapCRLFStripped }.joined(separator: " ")
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
        let sanitizedPath = destinationPath.imapQuoteSanitized
        _ = try await session.execute("UID COPY \(uidSet) \"\(sanitizedPath)\"")
    }

    /// Permanently removes messages from the currently selected folder.
    ///
    /// Sets \\Deleted flag and issues EXPUNGE.
    /// Per FR-SYNC-10: Archive = COPY + DELETE + EXPUNGE.
    public func expungeMessages(uids: [UInt32]) async throws {
        guard !uids.isEmpty else { return }

        // Batch-mark all messages as deleted in one round trip (not N)
        let uidSet = uids.map(String.init).joined(separator: ",")
        _ = try await session.execute("UID STORE \(uidSet) +FLAGS (\\Deleted)")

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

    // MARK: - IMAPClientProtocol: Body Part Fetch

    /// Fetches a single body part (attachment) by UID and MIME section.
    ///
    /// Maps to IMAP `UID FETCH <uid> (BODY.PEEK[<section>])`.
    /// Returns the raw body part data (still transfer-encoded).
    ///
    /// Per FR-SYNC-08: Attachments are downloaded lazily, on demand.
    public func fetchBodyPart(uid: UInt32, section: String) async throws -> Data {
        let command = "UID FETCH \(uid) (BODY.PEEK[\(section)])"
        let responses = try await session.execute(command)

        // Extract the body content from the FETCH response
        let sectionContent = IMAPResponseParser.extractBodyPartsBySection(
            from: responses.joined(separator: "\r\n")
        )

        guard let content = sectionContent[section] else {
            throw IMAPError.messageNotFound(String(uid))
        }

        // Return the raw bytes (caller handles transfer-encoding decoding)
        guard let data = content.data(using: .utf8) else {
            throw IMAPError.parsingFailed("Failed to decode body part data for UID \(uid) section \(section)")
        }

        return data
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
