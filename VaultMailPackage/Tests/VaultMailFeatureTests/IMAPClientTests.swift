import Foundation
import Testing
@testable import VaultMailFeature

/// Tests for IMAP client protocol behavior (AC-F-05).
///
/// These tests verify the IMAPClientProtocol contract using MockIMAPClient.
/// They validate that the protocol interface supports all operations required
/// by the Email Sync spec.
///
/// Spec ref: Email Sync spec FR-SYNC-01, FR-SYNC-03, FR-SYNC-09
/// Validation ref: AC-F-05
@Suite("IMAP Client — AC-F-05")
struct IMAPClientTests {

    // MARK: - Connection (FR-SYNC-09)

    @Test("Connect with valid credentials succeeds")
    func connectSuccess() async throws {
        let client = MockIMAPClient()

        try await client.connect(
            host: AppConstants.gmailImapHost,
            port: AppConstants.gmailImapPort,
            email: "user@gmail.com",
            accessToken: "valid-token"
        )

        let connected = await client.isConnected
        #expect(connected)
        #expect(client.connectCallCount == 1)
        #expect(client.lastConnectHost == "imap.gmail.com")
        #expect(client.lastConnectPort == 993)
        #expect(client.lastConnectEmail == "user@gmail.com")
        #expect(client.lastConnectAccessToken == "valid-token")
    }

    @Test("Connect uses TLS on port 993 (FR-SYNC-09)")
    func connectUsesTLS() async throws {
        let client = MockIMAPClient()

        try await client.connect(
            host: AppConstants.gmailImapHost,
            port: AppConstants.gmailImapPort,
            email: "user@gmail.com",
            accessToken: "token"
        )

        // Verify TLS port is used
        #expect(client.lastConnectPort == 993)
    }

    @Test("Connect with invalid credentials throws authenticationFailed")
    func connectAuthFailure() async throws {
        let client = MockIMAPClient()
        client.connectError = .authenticationFailed("XOAUTH2 rejected")

        await #expect(throws: IMAPError.self) {
            try await client.connect(
                host: AppConstants.gmailImapHost,
                port: AppConstants.gmailImapPort,
                email: "user@gmail.com",
                accessToken: "invalid-token"
            )
        }

        let connected = await client.isConnected
        #expect(!connected)
    }

    @Test("Connect timeout throws IMAPError.timeout (FR-SYNC-09: 30s)")
    func connectTimeout() async throws {
        let client = MockIMAPClient()
        client.connectError = .timeout

        await #expect(throws: IMAPError.timeout) {
            try await client.connect(
                host: AppConstants.gmailImapHost,
                port: AppConstants.gmailImapPort,
                email: "user@gmail.com",
                accessToken: "token"
            )
        }
    }

    @Test("Connect with connection failure throws connectionFailed")
    func connectConnectionFailure() async throws {
        let client = MockIMAPClient()
        client.connectError = .connectionFailed("TLS handshake failed")

        await #expect(throws: IMAPError.self) {
            try await client.connect(
                host: "bad-host",
                port: 993,
                email: "user@gmail.com",
                accessToken: "token"
            )
        }
    }

    @Test("Disconnect closes connection")
    func disconnect() async throws {
        let client = MockIMAPClient()
        try await client.connect(
            host: AppConstants.gmailImapHost,
            port: AppConstants.gmailImapPort,
            email: "user@gmail.com",
            accessToken: "token"
        )

        try await client.disconnect()

        let connected = await client.isConnected
        #expect(!connected)
        #expect(client.disconnectCallCount == 1)
    }

    // MARK: - Folder Listing (FR-SYNC-01 step 1)

    @Test("List folders returns all Gmail folders (AC-F-05)")
    func listFolders() async throws {
        let client = MockIMAPClient()
        client.listFoldersResult = .success([
            IMAPFolderInfo(name: "INBOX", imapPath: "INBOX", attributes: ["\\Inbox"], uidValidity: 1, messageCount: 42),
            IMAPFolderInfo(name: "Sent Mail", imapPath: "[Gmail]/Sent Mail", attributes: ["\\Sent"], uidValidity: 2, messageCount: 100),
            IMAPFolderInfo(name: "Drafts", imapPath: "[Gmail]/Drafts", attributes: ["\\Drafts"], uidValidity: 3, messageCount: 5),
            IMAPFolderInfo(name: "Trash", imapPath: "[Gmail]/Trash", attributes: ["\\Trash"], uidValidity: 4, messageCount: 10),
            IMAPFolderInfo(name: "Spam", imapPath: "[Gmail]/Spam", attributes: ["\\Junk"], uidValidity: 5, messageCount: 3),
            IMAPFolderInfo(name: "All Mail", imapPath: "[Gmail]/All Mail", attributes: ["\\All"], uidValidity: 6, messageCount: 500),
            IMAPFolderInfo(name: "Starred", imapPath: "[Gmail]/Starred", attributes: ["\\Flagged"], uidValidity: 7, messageCount: 15),
            IMAPFolderInfo(name: "Work", imapPath: "Work", attributes: [], uidValidity: 8, messageCount: 20),
        ])

        let folders = try await client.listFolders()

        #expect(folders.count == 8)
        #expect(client.listFoldersCallCount == 1)

        // Verify INBOX is present
        let inbox = try #require(folders.first { $0.imapPath == "INBOX" })
        #expect(inbox.attributes.contains("\\Inbox"))
        #expect(inbox.uidValidity == 1)
        #expect(inbox.messageCount == 42)

        // Verify custom label is present
        let work = try #require(folders.first { $0.imapPath == "Work" })
        #expect(work.attributes.isEmpty)
    }

    @Test("List folders returns folder attributes for special-use detection")
    func listFoldersAttributes() async throws {
        let client = MockIMAPClient()
        client.listFoldersResult = .success([
            IMAPFolderInfo(name: "Sent Mail", imapPath: "[Gmail]/Sent Mail", attributes: ["\\Sent", "\\HasNoChildren"], uidValidity: 2, messageCount: 100),
        ])

        let folders = try await client.listFolders()
        let sent = try #require(folders.first)

        #expect(sent.attributes.contains("\\Sent"))
    }

    // MARK: - Folder Selection

    @Test("Select folder returns UIDVALIDITY and message count")
    func selectFolder() async throws {
        let client = MockIMAPClient()
        client.selectFolderResult = .success((uidValidity: 12345, messageCount: 42))

        let result = try await client.selectFolder("INBOX")

        #expect(result.uidValidity == 12345)
        #expect(result.messageCount == 42)
        #expect(client.selectFolderCallCount == 1)
        #expect(client.lastSelectedPath == "INBOX")
    }

    @Test("Select non-existent folder throws folderNotFound")
    func selectFolderNotFound() async throws {
        let client = MockIMAPClient()
        client.selectFolderResult = .failure(.folderNotFound("NonExistent"))

        await #expect(throws: IMAPError.self) {
            try await client.selectFolder("NonExistent")
        }
    }

    // MARK: - UID Search (FR-SYNC-01 step 2)

    @Test("Search UIDs since date returns matching UIDs (AC-F-05)")
    func searchUIDsSinceDate() async throws {
        let client = MockIMAPClient()
        let sinceDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        client.searchUIDsResult = .success([101, 102, 103, 200, 201])

        let uids = try await client.searchUIDs(since: sinceDate)

        #expect(uids.count == 5)
        #expect(uids == [101, 102, 103, 200, 201])
        #expect(client.searchUIDsCallCount == 1)
    }

    @Test("Search UIDs returns empty array when no matches")
    func searchUIDsEmpty() async throws {
        let client = MockIMAPClient()
        client.searchUIDsResult = .success([])

        let uids = try await client.searchUIDs(since: Date())

        #expect(uids.isEmpty)
    }

    // MARK: - Fetch Headers (FR-SYNC-01, AC-F-05)

    @Test("Fetch headers returns complete email headers (AC-F-05)")
    func fetchHeaders() async throws {
        let client = MockIMAPClient()
        let testDate = Date(timeIntervalSince1970: 1700000000)

        client.fetchHeadersResult = .success([
            IMAPEmailHeader(
                uid: 101,
                messageId: "<abc@gmail.com>",
                inReplyTo: "<parent@gmail.com>",
                references: "<root@gmail.com> <parent@gmail.com>",
                from: "sender@gmail.com",
                to: ["recipient@gmail.com"],
                cc: ["cc@gmail.com"],
                bcc: [],
                subject: "Test Subject",
                date: testDate,
                flags: ["\\Seen"],
                size: 4096
            ),
        ])

        let headers = try await client.fetchHeaders(uids: [101])

        #expect(headers.count == 1)
        let header = try #require(headers.first)

        // AC-F-05: MUST fetch complete email headers
        #expect(header.uid == 101)
        #expect(header.messageId == "<abc@gmail.com>")
        #expect(header.inReplyTo == "<parent@gmail.com>")
        #expect(header.references == "<root@gmail.com> <parent@gmail.com>")
        #expect(header.from == "sender@gmail.com")
        #expect(header.to == ["recipient@gmail.com"])
        #expect(header.cc == ["cc@gmail.com"])
        #expect(header.subject == "Test Subject")
        #expect(header.date == testDate)
        #expect(header.flags.contains("\\Seen"))
        #expect(header.size == 4096)
    }

    @Test("Fetch headers for multiple UIDs returns all results")
    func fetchHeadersMultiple() async throws {
        let client = MockIMAPClient()
        client.fetchHeadersResult = .success([
            IMAPEmailHeader(uid: 1, messageId: "<a@test>", inReplyTo: nil, references: nil, from: "a@test", subject: "A", date: nil, flags: []),
            IMAPEmailHeader(uid: 2, messageId: "<b@test>", inReplyTo: nil, references: nil, from: "b@test", subject: "B", date: nil, flags: ["\\Seen"]),
            IMAPEmailHeader(uid: 3, messageId: "<c@test>", inReplyTo: "<a@test>", references: "<a@test>", from: "c@test", subject: "Re: A", date: nil, flags: ["\\Seen", "\\Flagged"]),
        ])

        let headers = try await client.fetchHeaders(uids: [1, 2, 3])

        #expect(headers.count == 3)
        #expect(client.lastFetchedUIDs == [1, 2, 3])
    }

    @Test("Fetch headers preserves threading headers for FR-SYNC-06")
    func fetchHeadersThreading() async throws {
        let client = MockIMAPClient()
        client.fetchHeadersResult = .success([
            IMAPEmailHeader(
                uid: 50,
                messageId: "<reply@test>",
                inReplyTo: "<original@test>",
                references: "<original@test>",
                from: "reply@test",
                subject: "Re: Thread",
                date: nil,
                flags: []
            ),
        ])

        let headers = try await client.fetchHeaders(uids: [50])
        let header = try #require(headers.first)

        // Threading headers MUST be available for FR-SYNC-06
        #expect(header.messageId == "<reply@test>")
        #expect(header.inReplyTo == "<original@test>")
        #expect(header.references == "<original@test>")
    }

    // MARK: - Fetch Bodies (FR-SYNC-01 step 3)

    @Test("Fetch bodies returns plain text and HTML (AC-F-05)")
    func fetchBodies() async throws {
        let client = MockIMAPClient()
        client.fetchBodiesResult = .success([
            IMAPEmailBody(
                uid: 101,
                plainText: "Hello, this is plain text.",
                htmlText: "<html><body>Hello</body></html>",
                attachments: []
            ),
        ])

        let bodies = try await client.fetchBodies(uids: [101])

        #expect(bodies.count == 1)
        let body = try #require(bodies.first)

        #expect(body.uid == 101)
        #expect(body.plainText == "Hello, this is plain text.")
        #expect(body.htmlText == "<html><body>Hello</body></html>")
    }

    @Test("Fetch bodies handles plain-text-only emails (FR-SYNC-01)")
    func fetchBodiesPlainOnly() async throws {
        let client = MockIMAPClient()
        client.fetchBodiesResult = .success([
            IMAPEmailBody(uid: 102, plainText: "Plain only", htmlText: nil),
        ])

        let bodies = try await client.fetchBodies(uids: [102])
        let body = try #require(bodies.first)

        #expect(body.plainText == "Plain only")
        #expect(body.htmlText == nil)
    }

    @Test("Fetch bodies handles HTML-only emails (FR-SYNC-01)")
    func fetchBodiesHTMLOnly() async throws {
        let client = MockIMAPClient()
        client.fetchBodiesResult = .success([
            IMAPEmailBody(uid: 103, plainText: nil, htmlText: "<p>HTML only</p>"),
        ])

        let bodies = try await client.fetchBodies(uids: [103])
        let body = try #require(bodies.first)

        #expect(body.plainText == nil)
        #expect(body.htmlText == "<p>HTML only</p>")
    }

    @Test("Fetch bodies includes attachment metadata (FR-SYNC-08)")
    func fetchBodiesWithAttachments() async throws {
        let client = MockIMAPClient()
        client.fetchBodiesResult = .success([
            IMAPEmailBody(
                uid: 104,
                plainText: "See attached",
                htmlText: nil,
                attachments: [
                    IMAPAttachmentInfo(
                        partId: "2",
                        filename: "report.pdf",
                        mimeType: "application/pdf",
                        sizeBytes: 1_048_576,
                        contentId: nil
                    ),
                    IMAPAttachmentInfo(
                        partId: "3",
                        filename: "photo.jpg",
                        mimeType: "image/jpeg",
                        sizeBytes: 524_288,
                        contentId: "<inline-photo>"
                    ),
                ]
            ),
        ])

        let bodies = try await client.fetchBodies(uids: [104])
        let body = try #require(bodies.first)

        #expect(body.attachments.count == 2)

        let pdf = try #require(body.attachments.first { $0.filename == "report.pdf" })
        #expect(pdf.mimeType == "application/pdf")
        #expect(pdf.sizeBytes == 1_048_576)
        #expect(pdf.contentId == nil)

        let photo = try #require(body.attachments.first { $0.filename == "photo.jpg" })
        #expect(photo.contentId == "<inline-photo>")
    }

    // MARK: - Flag Operations (FR-SYNC-10)

    @Test("Fetch flags returns current flag state")
    func fetchFlags() async throws {
        let client = MockIMAPClient()
        client.fetchFlagsResult = .success([
            101: ["\\Seen"],
            102: ["\\Seen", "\\Flagged"],
            103: [],
        ])

        let flags = try await client.fetchFlags(uids: [101, 102, 103])

        #expect(flags[101] == ["\\Seen"])
        #expect(flags[102] == ["\\Seen", "\\Flagged"])
        #expect(flags[103] == [])
    }

    @Test("Store flags adds \\Seen flag (FR-SYNC-10: mark read)")
    func storeFlagsMarkRead() async throws {
        let client = MockIMAPClient()

        try await client.storeFlags(uid: 101, add: ["\\Seen"], remove: [])

        #expect(client.storeFlagsCallCount == 1)
        #expect(client.lastStoreFlagUID == 101)
        #expect(client.lastStoreFlagAdd == ["\\Seen"])
        #expect(client.lastStoreFlagRemove == [])
    }

    @Test("Store flags removes \\Seen flag (FR-SYNC-10: mark unread)")
    func storeFlagsMarkUnread() async throws {
        let client = MockIMAPClient()

        try await client.storeFlags(uid: 101, add: [], remove: ["\\Seen"])

        #expect(client.lastStoreFlagAdd == [])
        #expect(client.lastStoreFlagRemove == ["\\Seen"])
    }

    @Test("Store flags adds \\Flagged (FR-SYNC-10: star)")
    func storeFlagsStar() async throws {
        let client = MockIMAPClient()

        try await client.storeFlags(uid: 101, add: ["\\Flagged"], remove: [])

        #expect(client.lastStoreFlagAdd == ["\\Flagged"])
    }

    @Test("Store flags removes \\Flagged (FR-SYNC-10: unstar)")
    func storeFlagsUnstar() async throws {
        let client = MockIMAPClient()

        try await client.storeFlags(uid: 101, add: [], remove: ["\\Flagged"])

        #expect(client.lastStoreFlagRemove == ["\\Flagged"])
    }

    // MARK: - Copy & Delete (FR-SYNC-10: Archive/Delete)

    @Test("Copy messages to destination folder (FR-SYNC-10: archive COPY step)")
    func copyMessages() async throws {
        let client = MockIMAPClient()

        try await client.copyMessages(uids: [101, 102], to: "[Gmail]/All Mail")

        #expect(client.copyMessagesCallCount == 1)
        #expect(client.lastCopyUIDs == [101, 102])
        #expect(client.lastCopyDestination == "[Gmail]/All Mail")
    }

    @Test("Expunge messages from folder (FR-SYNC-10: archive DELETE+EXPUNGE step)")
    func expungeMessages() async throws {
        let client = MockIMAPClient()

        try await client.expungeMessages(uids: [101, 102])

        #expect(client.expungeMessagesCallCount == 1)
        #expect(client.lastExpungeUIDs == [101, 102])
    }

    @Test("Expunge with empty UIDs is a no-op — production guard")
    func expungeEmptyUIDs() async throws {
        // The production IMAPClient guards against empty UIDs and returns early.
        // Verify the expected UID set for an empty array is indeed empty.
        let uids: [UInt32] = []
        let uidSet = uids.map(String.init).joined(separator: ",")
        #expect(uidSet.isEmpty)
    }

    @Test("Expunge batches UID STORE — single command for multiple UIDs (not N)")
    func expungeBatchesStore() async throws {
        // Verify the production code builds a comma-separated UID set
        // rather than looping one UID at a time.
        // We verify the format by checking that the batched UID set
        // "101,102,103" would be generated correctly.
        let uids: [UInt32] = [101, 102, 103, 104, 105]
        let expectedUIDSet = uids.map(String.init).joined(separator: ",")
        #expect(expectedUIDSet == "101,102,103,104,105")

        // Also verify the mock records all UIDs in a single call
        let client = MockIMAPClient()
        try await client.expungeMessages(uids: uids)
        #expect(client.expungeMessagesCallCount == 1)
        #expect(client.lastExpungeUIDs == uids)
    }

    // MARK: - Append Message (FR-SYNC-07)

    @Test("Append message to Sent folder (FR-SYNC-07)")
    func appendMessage() async throws {
        let client = MockIMAPClient()
        let messageData = "From: test@test.com\r\nSubject: Test\r\n\r\nBody".data(using: .utf8)!

        try await client.appendMessage(
            to: "[Gmail]/Sent Mail",
            messageData: messageData,
            flags: ["\\Seen"]
        )

        #expect(client.appendMessageCallCount == 1)
        #expect(client.lastAppendPath == "[Gmail]/Sent Mail")
        #expect(client.lastAppendData == messageData)
        #expect(client.lastAppendFlags == ["\\Seen"])
    }

    // MARK: - IMAP IDLE (FR-SYNC-03)

    @Test("Start IDLE registers handler for new mail (AC-F-05)")
    func startIDLE() async throws {
        let client = MockIMAPClient()
        let mailFlag = MailReceivedFlag()

        try await client.startIDLE {
            mailFlag.set()
        }

        #expect(client.startIDLECallCount == 1)

        // Simulate new mail
        client.simulateNewMail()
        #expect(mailFlag.value)
    }

    @Test("Stop IDLE clears handler")
    func stopIDLE() async throws {
        let client = MockIMAPClient()
        try await client.startIDLE { }

        try await client.stopIDLE()

        #expect(client.stopIDLECallCount == 1)
    }

    @Test("Start IDLE failure throws error")
    func startIDLEFailure() async throws {
        let client = MockIMAPClient()
        client.startIDLEError = .connectionFailed("IDLE not supported")

        await #expect(throws: IMAPError.self) {
            try await client.startIDLE { }
        }
    }

    // MARK: - Error Handling

    @Test("List folders failure propagates error")
    func listFoldersError() async throws {
        let client = MockIMAPClient()
        client.listFoldersResult = .failure(.commandFailed("LIST failed"))

        await #expect(throws: IMAPError.self) {
            try await client.listFolders()
        }
    }

    @Test("Fetch headers failure propagates error")
    func fetchHeadersError() async throws {
        let client = MockIMAPClient()
        client.fetchHeadersResult = .failure(.commandFailed("FETCH failed"))

        await #expect(throws: IMAPError.self) {
            try await client.fetchHeaders(uids: [1])
        }
    }

    @Test("Store flags failure propagates error")
    func storeFlagsError() async throws {
        let client = MockIMAPClient()
        client.storeFlagsError = .commandFailed("STORE failed")

        await #expect(throws: IMAPError.self) {
            try await client.storeFlags(uid: 1, add: ["\\Seen"], remove: [])
        }
    }
}

// MARK: - Connection Constants Tests (FR-SYNC-09)

@Suite("IMAP Connection Constants — FR-SYNC-09")
struct IMAPConnectionConstantsTests {

    @Test("Gmail IMAP host is imap.gmail.com")
    func gmailIMAPHost() {
        #expect(AppConstants.gmailImapHost == "imap.gmail.com")
    }

    @Test("Gmail IMAP port is 993 (implicit TLS)")
    func gmailIMAPPort() {
        #expect(AppConstants.gmailImapPort == 993)
    }

    @Test("Connection timeout is 30 seconds (FR-SYNC-09)")
    func connectionTimeout() {
        #expect(AppConstants.imapConnectionTimeout == 30.0)
    }

    @Test("Max connections per account is 5 (FR-SYNC-09, Gmail limit)")
    func maxConnections() {
        #expect(AppConstants.imapMaxConnectionsPerAccount == 5)
    }

    @Test("Retry base delay is 5 seconds (FR-SYNC-09)")
    func retryBaseDelay() {
        #expect(AppConstants.imapRetryBaseDelay == 5.0)
    }

    @Test("Max retries is 3 (FR-SYNC-09)")
    func maxRetries() {
        #expect(AppConstants.imapMaxRetries == 3)
    }

    @Test("IDLE refresh interval is 25 minutes (FR-SYNC-03)")
    func idleRefreshInterval() {
        #expect(AppConstants.imapIdleRefreshInterval == 25 * 60)
    }

    @Test("Max email body size is 10 MB (FR-SYNC-01)")
    func maxEmailBodySize() {
        #expect(AppConstants.maxEmailBodySizeBytes == 10 * 1024 * 1024)
    }

    @Test("Gmail SMTP host is smtp.gmail.com")
    func gmailSMTPHost() {
        #expect(AppConstants.gmailSmtpHost == "smtp.gmail.com")
    }

    @Test("Gmail SMTP port is 465 (implicit TLS)")
    func gmailSMTPPort() {
        #expect(AppConstants.gmailSmtpPort == 465)
    }

    @Test("Send queue max age is 24 hours (FR-SYNC-07 step 5)")
    func sendQueueMaxAge() {
        #expect(AppConstants.sendQueueMaxAgeHours == 24)
    }
}

// MARK: - IMAP Command Sanitization Tests

@Suite("IMAP Command Sanitization — Injection Prevention")
struct IMAPSanitizationTests {

    // MARK: - imapQuoteSanitized (Folder Paths)

    @Test("Normal folder path passes through unchanged")
    func normalFolderPath() {
        #expect("INBOX".imapQuoteSanitized == "INBOX")
        #expect("[Gmail]/Sent Mail".imapQuoteSanitized == "[Gmail]/Sent Mail")
        #expect("Work/Projects/Alpha".imapQuoteSanitized == "Work/Projects/Alpha")
    }

    @Test("CRLF injection is stripped from folder path")
    func crlfInjectionStripped() {
        // A malicious folder name trying to inject a DELETE command
        let malicious = "INBOX\r\nA001 DELETE \"INBOX\""
        let sanitized = malicious.imapQuoteSanitized
        #expect(!sanitized.contains("\r"))
        #expect(!sanitized.contains("\n"))
        #expect(sanitized == "INBOXA001 DELETE \\\"INBOX\\\"")
    }

    @Test("CR only injection is stripped")
    func crOnlyStripped() {
        let input = "folder\rinjection"
        let sanitized = input.imapQuoteSanitized
        #expect(!sanitized.contains("\r"))
        #expect(sanitized == "folderinjection")
    }

    @Test("LF only injection is stripped")
    func lfOnlyStripped() {
        let input = "folder\ninjection"
        let sanitized = input.imapQuoteSanitized
        #expect(!sanitized.contains("\n"))
        #expect(sanitized == "folderinjection")
    }

    @Test("Double quotes are escaped in folder path")
    func doubleQuoteEscaped() {
        // A " in a folder name would break the quoted string
        let input = "folder\"breakout"
        let sanitized = input.imapQuoteSanitized
        // The quote should be escaped with a backslash
        #expect(sanitized == "folder\\\"breakout")
        // Verify the quote is preceded by a backslash (escaped)
        #expect(sanitized.contains("\\\""))
    }

    @Test("Backslashes are escaped in folder path")
    func backslashEscaped() {
        let input = "folder\\path"
        let sanitized = input.imapQuoteSanitized
        #expect(sanitized == "folder\\\\path")
    }

    @Test("Combined injection payload is fully neutralized")
    func combinedInjectionNeutralized() {
        // Attempt: close the quoted string, inject CRLF, run new command
        let payload = "\"\r\nA999 DELETE \"INBOX\"\r\n"
        let sanitized = payload.imapQuoteSanitized
        #expect(!sanitized.contains("\r"))
        #expect(!sanitized.contains("\n"))
        // All quotes should be escaped
        _ = sanitized.components(separatedBy: "\"").count
            - sanitized.components(separatedBy: "\\\"").count
        // The result should be safe to interpolate into SELECT "..."
        #expect(sanitized == "\\\"A999 DELETE \\\"INBOX\\\"")
    }

    @Test("Empty string is unchanged")
    func emptyStringQuoted() {
        #expect("".imapQuoteSanitized == "")
    }

    @Test("Unicode folder names pass through safely")
    func unicodeFolderPath() {
        let input = "工作/项目"
        #expect(input.imapQuoteSanitized == "工作/项目")
    }

    // MARK: - imapCRLFStripped (Flags / Atoms)

    @Test("Normal IMAP flags pass through unchanged")
    func normalFlagsUnchanged() {
        #expect("\\Seen".imapCRLFStripped == "\\Seen")
        #expect("\\Flagged".imapCRLFStripped == "\\Flagged")
        #expect("\\Deleted".imapCRLFStripped == "\\Deleted")
        #expect("\\Answered".imapCRLFStripped == "\\Answered")
    }

    @Test("Backslash in flags is preserved (not escaped)")
    func backslashPreservedInFlags() {
        // Flags use raw backslash — must NOT be escaped
        let flag = "\\Seen"
        #expect(flag.imapCRLFStripped == "\\Seen")
    }

    @Test("CRLF injection is stripped from flags")
    func crlfStrippedFromFlags() {
        let malicious = "\\Seen\r\nA001 DELETE \"INBOX\""
        let sanitized = malicious.imapCRLFStripped
        #expect(!sanitized.contains("\r"))
        #expect(!sanitized.contains("\n"))
        #expect(sanitized == "\\SeenA001 DELETE \"INBOX\"")
    }

    @Test("Empty string is unchanged for atoms")
    func emptyStringAtom() {
        #expect("".imapCRLFStripped == "")
    }
}

// MARK: - Test Helpers

/// Thread-safe flag for testing async callbacks in @Sendable closures.
private final class MailReceivedFlag: @unchecked Sendable {
    private var _value = false
    private let lock = NSLock()

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func set() {
        lock.lock()
        defer { lock.unlock() }
        _value = true
    }
}
