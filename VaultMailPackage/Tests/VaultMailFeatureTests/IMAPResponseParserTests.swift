import Foundation
import Testing
@testable import VaultMailFeature

/// Tests for the IMAP response parser.
///
/// Validates that raw IMAP server responses are correctly parsed into
/// structured DTOs (IMAPFolderInfo, IMAPEmailHeader, IMAPEmailBody).
/// This is a critical component — if parsing is wrong, every downstream
/// sync operation will produce incorrect data.
///
/// Spec ref: FR-SYNC-01 (Folder discovery, Email sync, Body format, Attachments)
/// Spec ref: FR-SYNC-02 (UIDVALIDITY for incremental sync)
/// Spec ref: FR-SYNC-10 (Flag parsing for bidirectional flag sync)
/// Validation ref: AC-F-05
@Suite("IMAP Response Parser — FR-SYNC-01")
struct IMAPResponseParserTests {

    // MARK: - LIST Response Parsing (FR-SYNC-01 step 1)

    @Test("Parses standard LIST response with attributes")
    func parseListStandard() {
        let line = #"* LIST (\HasNoChildren \Sent) "/" "[Gmail]/Sent Mail""#
        let result = IMAPResponseParser.parseListResponse(line)

        #expect(result != nil)
        #expect(result?.imapPath == "[Gmail]/Sent Mail")
        #expect(result?.name == "Sent Mail")
        #expect(result?.attributes.contains("\\HasNoChildren") == true)
        #expect(result?.attributes.contains("\\Sent") == true)
    }

    @Test("Parses INBOX LIST response")
    func parseListInbox() {
        let line = #"* LIST (\HasNoChildren \Inbox) "/" "INBOX""#
        let result = IMAPResponseParser.parseListResponse(line)

        #expect(result != nil)
        #expect(result?.imapPath == "INBOX")
        #expect(result?.name == "INBOX")
        #expect(result?.attributes.contains("\\Inbox") == true)
    }

    @Test("Parses LIST response with no attributes")
    func parseListNoAttributes() {
        let line = #"* LIST () "/" "Work/Projects""#
        let result = IMAPResponseParser.parseListResponse(line)

        #expect(result != nil)
        #expect(result?.imapPath == "Work/Projects")
        #expect(result?.name == "Projects")
        #expect(result?.attributes.isEmpty == true)
    }

    @Test("Parses LIST response for [Gmail] container with \\Noselect")
    func parseListGmailContainer() {
        let line = #"* LIST (\Noselect \HasChildren) "/" "[Gmail]""#
        let result = IMAPResponseParser.parseListResponse(line)

        #expect(result != nil)
        #expect(result?.imapPath == "[Gmail]")
        #expect(result?.name == "[Gmail]")
        #expect(result?.attributes.contains("\\Noselect") == true)
        #expect(result?.attributes.contains("\\HasChildren") == true)
    }

    @Test("Parses LIST response for All Mail (\\All attribute)")
    func parseListAllMail() {
        let line = #"* LIST (\All \HasNoChildren) "/" "[Gmail]/All Mail""#
        let result = IMAPResponseParser.parseListResponse(line)

        #expect(result != nil)
        #expect(result?.imapPath == "[Gmail]/All Mail")
        #expect(result?.attributes.contains("\\All") == true)
    }

    @Test("Parses LIST response for Trash (\\Trash attribute)")
    func parseListTrash() {
        let line = #"* LIST (\Trash \HasNoChildren) "/" "[Gmail]/Trash""#
        let result = IMAPResponseParser.parseListResponse(line)

        #expect(result != nil)
        #expect(result?.imapPath == "[Gmail]/Trash")
        #expect(result?.attributes.contains("\\Trash") == true)
    }

    @Test("Parses LIST response for Spam (\\Junk attribute)")
    func parseListSpam() {
        let line = #"* LIST (\Junk \HasNoChildren) "/" "[Gmail]/Spam""#
        let result = IMAPResponseParser.parseListResponse(line)

        #expect(result != nil)
        #expect(result?.imapPath == "[Gmail]/Spam")
        #expect(result?.attributes.contains("\\Junk") == true)
    }

    @Test("Parses LIST response for Starred (\\Flagged attribute)")
    func parseListStarred() {
        let line = #"* LIST (\Flagged \HasNoChildren) "/" "[Gmail]/Starred""#
        let result = IMAPResponseParser.parseListResponse(line)

        #expect(result != nil)
        #expect(result?.imapPath == "[Gmail]/Starred")
        #expect(result?.attributes.contains("\\Flagged") == true)
    }

    @Test("Parses LIST response for Drafts (\\Drafts attribute)")
    func parseListDrafts() {
        let line = #"* LIST (\Drafts \HasNoChildren) "/" "[Gmail]/Drafts""#
        let result = IMAPResponseParser.parseListResponse(line)

        #expect(result != nil)
        #expect(result?.imapPath == "[Gmail]/Drafts")
        #expect(result?.attributes.contains("\\Drafts") == true)
    }

    @Test("Returns nil for non-LIST response")
    func parseListNonList() {
        let line = "* OK [UIDVALIDITY 12345]"
        let result = IMAPResponseParser.parseListResponse(line)
        #expect(result == nil)
    }

    @Test("Returns nil for empty string")
    func parseListEmpty() {
        let result = IMAPResponseParser.parseListResponse("")
        #expect(result == nil)
    }

    @Test("Returns nil for malformed LIST response (no parentheses)")
    func parseListMalformed() {
        let line = "* LIST no-parens / INBOX"
        let result = IMAPResponseParser.parseListResponse(line)
        #expect(result == nil)
    }

    @Test("LIST uidValidity defaults to 0 (populated later on SELECT)")
    func parseListUidValidityDefault() {
        let line = #"* LIST (\Inbox) "/" "INBOX""#
        let result = IMAPResponseParser.parseListResponse(line)

        #expect(result?.uidValidity == 0)
        #expect(result?.messageCount == 0)
    }

    @Test("Parses multiple LIST responses correctly")
    func parseMultipleListResponses() {
        let lines = [
            #"* LIST (\Inbox) "/" "INBOX""#,
            #"* LIST (\Sent) "/" "[Gmail]/Sent Mail""#,
            #"* LIST (\Drafts) "/" "[Gmail]/Drafts""#,
            #"* LIST () "/" "Work""#,
        ]

        let results = lines.compactMap { IMAPResponseParser.parseListResponse($0) }

        #expect(results.count == 4)
        #expect(results[0].imapPath == "INBOX")
        #expect(results[1].imapPath == "[Gmail]/Sent Mail")
        #expect(results[2].imapPath == "[Gmail]/Drafts")
        #expect(results[3].imapPath == "Work")
    }

    // MARK: - SELECT Response Parsing (FR-SYNC-02: UIDVALIDITY)

    @Test("Parses UIDVALIDITY from SELECT response")
    func parseUIDValidity() {
        let responses = [
            "* 42 EXISTS",
            "* 1 RECENT",
            "* OK [UIDVALIDITY 12345] UIDs valid",
            "* OK [UIDNEXT 500] Predicted next UID",
        ]

        let uidValidity = IMAPResponseParser.parseUIDValidity(from: responses)
        #expect(uidValidity == 12345)
    }

    @Test("UIDVALIDITY returns 0 when not present")
    func parseUIDValidityMissing() {
        let responses = [
            "* 42 EXISTS",
            "* OK Some other info",
        ]

        let uidValidity = IMAPResponseParser.parseUIDValidity(from: responses)
        #expect(uidValidity == 0)
    }

    @Test("UIDVALIDITY returns 0 for empty response array")
    func parseUIDValidityEmpty() {
        let uidValidity = IMAPResponseParser.parseUIDValidity(from: [])
        #expect(uidValidity == 0)
    }

    @Test("Parses large UIDVALIDITY values")
    func parseUIDValidityLarge() {
        let responses = ["* OK [UIDVALIDITY 4294967295] Max UInt32"]

        let uidValidity = IMAPResponseParser.parseUIDValidity(from: responses)
        #expect(uidValidity == 4294967295)
    }

    @Test("Parses EXISTS count from SELECT response")
    func parseExists() {
        let responses = [
            "* 42 EXISTS",
            "* 1 RECENT",
            "* OK [UIDVALIDITY 12345]",
        ]

        let exists = IMAPResponseParser.parseExists(from: responses)
        #expect(exists == 42)
    }

    @Test("EXISTS returns 0 when not present")
    func parseExistsMissing() {
        let responses = [
            "* 1 RECENT",
            "* OK [UIDVALIDITY 12345]",
        ]

        let exists = IMAPResponseParser.parseExists(from: responses)
        #expect(exists == 0)
    }

    @Test("EXISTS returns 0 for empty folder")
    func parseExistsZero() {
        let responses = ["* 0 EXISTS"]
        let exists = IMAPResponseParser.parseExists(from: responses)
        #expect(exists == 0)
    }

    @Test("EXISTS returns 0 for empty response array")
    func parseExistsEmpty() {
        let exists = IMAPResponseParser.parseExists(from: [])
        #expect(exists == 0)
    }

    @Test("Parses large EXISTS count")
    func parseExistsLarge() {
        let responses = ["* 99999 EXISTS"]
        let exists = IMAPResponseParser.parseExists(from: responses)
        #expect(exists == 99999)
    }

    // MARK: - SEARCH Response Parsing (FR-SYNC-01 step 2)

    @Test("Parses SEARCH response with multiple UIDs")
    func parseSearchMultiple() {
        let responses = ["* SEARCH 101 102 103 200 201"]

        let uids = IMAPResponseParser.parseSearchResponse(from: responses)
        #expect(uids == [101, 102, 103, 200, 201])
    }

    @Test("Parses SEARCH response with single UID")
    func parseSearchSingle() {
        let responses = ["* SEARCH 42"]

        let uids = IMAPResponseParser.parseSearchResponse(from: responses)
        #expect(uids == [42])
    }

    @Test("Parses empty SEARCH response (no matches)")
    func parseSearchEmpty() {
        let responses = ["* SEARCH"]

        let uids = IMAPResponseParser.parseSearchResponse(from: responses)
        #expect(uids.isEmpty)
    }

    @Test("SEARCH returns empty for no SEARCH line")
    func parseSearchMissing() {
        let responses = ["* OK completed"]

        let uids = IMAPResponseParser.parseSearchResponse(from: responses)
        #expect(uids.isEmpty)
    }

    @Test("SEARCH returns empty for empty response array")
    func parseSearchEmptyArray() {
        let uids = IMAPResponseParser.parseSearchResponse(from: [])
        #expect(uids.isEmpty)
    }

    @Test("SEARCH ignores non-numeric values")
    func parseSearchNonNumeric() {
        let responses = ["* SEARCH 101 abc 103"]

        let uids = IMAPResponseParser.parseSearchResponse(from: responses)
        // compactMap should skip "abc"
        #expect(uids == [101, 103])
    }

    // MARK: - FETCH Header Parsing (AC-F-05)

    @Test("Parses FETCH header response with all fields (AC-F-05)")
    func parseHeaderComplete() {
        let response = """
        * 1 FETCH (UID 101 FLAGS (\\Seen) RFC822.SIZE 4096 BODY[HEADER.FIELDS (FROM TO CC BCC SUBJECT DATE MESSAGE-ID IN-REPLY-TO REFERENCES)] {200}
        From: sender@gmail.com
        To: recipient@gmail.com
        CC: cc@gmail.com
        Subject: Test Subject
        Date: Mon, 1 Jan 2024 12:00:00 +0000
        Message-ID: <abc123@gmail.com>
        In-Reply-To: <parent@gmail.com>
        References: <root@gmail.com> <parent@gmail.com>

        """

        let headers = IMAPResponseParser.parseHeaderResponses([response])

        #expect(headers.count == 1)
        let header = headers[0]

        #expect(header.uid == 101)
        #expect(header.from == "sender@gmail.com")
        #expect(header.to == ["recipient@gmail.com"])
        #expect(header.cc == ["cc@gmail.com"])
        #expect(header.subject == "Test Subject")
        #expect(header.messageId == "<abc123@gmail.com>")
        #expect(header.inReplyTo == "<parent@gmail.com>")
        #expect(header.references == "<root@gmail.com> <parent@gmail.com>")
        #expect(header.flags.contains("\\Seen"))
        #expect(header.size == 4096)
    }

    @Test("Parses FETCH header with multiple recipients")
    func parseHeaderMultipleRecipients() {
        let response = """
        * 1 FETCH (UID 200 FLAGS () RFC822.SIZE 2048 BODY[HEADER.FIELDS (FROM TO CC)] {100}
        From: sender@test.com
        To: user1@test.com, user2@test.com, user3@test.com
        CC: cc1@test.com, cc2@test.com

        """

        let headers = IMAPResponseParser.parseHeaderResponses([response])
        #expect(headers.count == 1)

        let header = headers[0]
        #expect(header.to.count == 3)
        #expect(header.to.contains("user1@test.com"))
        #expect(header.to.contains("user2@test.com"))
        #expect(header.to.contains("user3@test.com"))
        #expect(header.cc.count == 2)
    }

    @Test("Parses FETCH header with multiple flags (FR-SYNC-10)")
    func parseHeaderMultipleFlags() {
        let response = "* 1 FETCH (UID 300 FLAGS (\\Seen \\Flagged \\Answered) RFC822.SIZE 1024)"

        let headers = IMAPResponseParser.parseHeaderResponses([response])
        #expect(headers.count == 1)

        let header = headers[0]
        #expect(header.flags.contains("\\Seen"))
        #expect(header.flags.contains("\\Flagged"))
        #expect(header.flags.contains("\\Answered"))
    }

    @Test("Parses FETCH header with no flags")
    func parseHeaderNoFlags() {
        let response = "* 1 FETCH (UID 400 FLAGS () RFC822.SIZE 512)"

        let headers = IMAPResponseParser.parseHeaderResponses([response])
        #expect(headers.count == 1)
        #expect(headers[0].flags.isEmpty)
    }

    @Test("Parses FETCH header extracting UID correctly")
    func parseHeaderUID() {
        let response = "* 1 FETCH (UID 99999 FLAGS () RFC822.SIZE 100)"

        let headers = IMAPResponseParser.parseHeaderResponses([response])
        #expect(headers.count == 1)
        #expect(headers[0].uid == 99999)
    }

    @Test("Ignores non-FETCH response lines")
    func parseHeaderIgnoresNonFetch() {
        let responses = [
            "* OK [UIDVALIDITY 12345]",
            "* 1 FETCH (UID 101 FLAGS () RFC822.SIZE 100)",
            "* OK completed",
        ]

        let headers = IMAPResponseParser.parseHeaderResponses(responses)
        #expect(headers.count == 1)
        #expect(headers[0].uid == 101)
    }

    @Test("Returns empty array for responses without FETCH")
    func parseHeaderEmptyFetch() {
        let responses = ["* OK completed", "* 42 EXISTS"]
        let headers = IMAPResponseParser.parseHeaderResponses(responses)
        #expect(headers.isEmpty)
    }

    @Test("Parses FETCH header with nil optional fields")
    func parseHeaderMinimal() {
        let response = "* 1 FETCH (UID 500 FLAGS () RFC822.SIZE 0)"

        let headers = IMAPResponseParser.parseHeaderResponses([response])
        #expect(headers.count == 1)

        let header = headers[0]
        #expect(header.uid == 500)
        #expect(header.messageId == nil)
        #expect(header.inReplyTo == nil)
        #expect(header.references == nil)
        #expect(header.from == nil)
        #expect(header.subject == nil)
        #expect(header.date == nil)
    }

    // MARK: - FETCH Flag Parsing (FR-SYNC-10)

    @Test("Parses flag responses for multiple UIDs (FR-SYNC-10)")
    func parseFlagResponses() {
        let responses = [
            "* 1 FETCH (UID 101 FLAGS (\\Seen))",
            "* 2 FETCH (UID 102 FLAGS (\\Seen \\Flagged))",
            "* 3 FETCH (UID 103 FLAGS ())",
        ]

        let flags = IMAPResponseParser.parseFlagResponses(responses)

        #expect(flags.count == 3)
        #expect(flags[101] == ["\\Seen"])
        #expect(flags[102] == ["\\Seen", "\\Flagged"])
        #expect(flags[103] == [])
    }

    @Test("Flag parsing returns empty for no FETCH responses")
    func parseFlagResponsesEmpty() {
        let responses = ["* OK completed"]
        let flags = IMAPResponseParser.parseFlagResponses(responses)
        #expect(flags.isEmpty)
    }

    @Test("Flag parsing handles \\Deleted flag")
    func parseFlagResponsesDeleted() {
        let responses = ["* 1 FETCH (UID 101 FLAGS (\\Deleted \\Seen))"]

        let flags = IMAPResponseParser.parseFlagResponses(responses)
        #expect(flags[101]?.contains("\\Deleted") == true)
        #expect(flags[101]?.contains("\\Seen") == true)
    }

    // MARK: - BODYSTRUCTURE Parsing (FR-SYNC-08)

    @Test("Parses simple text/plain BODYSTRUCTURE")
    func parseBodyStructureSimplePlain() {
        let response = #"* 1 FETCH (UID 101 BODYSTRUCTURE ("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" 1234 42))"#

        let parts = IMAPResponseParser.parseBodyStructure(from: response)

        #expect(parts.count == 1)
        #expect(parts[0].mimeType == "text/plain")
        #expect(parts[0].size == 1234)
        #expect(parts[0].isAttachment == false)
    }

    @Test("Parses simple text/html BODYSTRUCTURE")
    func parseBodyStructureSimpleHTML() {
        let response = #"* 1 FETCH (UID 101 BODYSTRUCTURE ("TEXT" "HTML" ("CHARSET" "UTF-8") NIL NIL "QUOTED-PRINTABLE" 5678 100))"#

        let parts = IMAPResponseParser.parseBodyStructure(from: response)

        #expect(parts.count == 1)
        #expect(parts[0].mimeType == "text/html")
        #expect(parts[0].size == 5678)
    }

    @Test("Parses multipart/alternative BODYSTRUCTURE (plain + HTML)")
    func parseBodyStructureMultipartAlternative() {
        let response = #"* 1 FETCH (UID 101 BODYSTRUCTURE (("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" 100 5)("TEXT" "HTML" ("CHARSET" "UTF-8") NIL NIL "QUOTED-PRINTABLE" 500 20) "ALTERNATIVE"))"#

        let parts = IMAPResponseParser.parseBodyStructure(from: response)

        #expect(parts.count == 2)

        let plainPart = parts.first { $0.mimeType == "text/plain" }
        let htmlPart = parts.first { $0.mimeType == "text/html" }

        #expect(plainPart != nil)
        #expect(htmlPart != nil)
        #expect(plainPart?.partId == "1")
        #expect(htmlPart?.partId == "2")
    }

    @Test("Returns empty for response without BODYSTRUCTURE")
    func parseBodyStructureMissing() {
        let response = "* 1 FETCH (UID 101 FLAGS (\\Seen))"
        let parts = IMAPResponseParser.parseBodyStructure(from: response)
        #expect(parts.isEmpty)
    }

    @Test("Returns empty for empty response")
    func parseBodyStructureEmpty() {
        let parts = IMAPResponseParser.parseBodyStructure(from: "")
        #expect(parts.isEmpty)
    }

    // MARK: - FETCH Body Parsing

    @Test("Parses body response extracting UID")
    func parseBodyResponseUID() {
        let response = "* 1 FETCH (UID 101 BODY[1] {20}\nHello plain text body)"

        let bodies = IMAPResponseParser.parseBodyResponses([response])
        #expect(bodies.count == 1)
        #expect(bodies[0].uid == 101)
    }

    @Test("Body parsing ignores non-FETCH lines")
    func parseBodyResponseIgnoresNonFetch() {
        let responses = [
            "* OK completed",
            "* 42 EXISTS",
        ]

        let bodies = IMAPResponseParser.parseBodyResponses(responses)
        #expect(bodies.isEmpty)
    }

    @Test("Body response returns empty attachments when none present")
    func parseBodyResponseNoAttachments() {
        let response = "* 1 FETCH (UID 101 BODY[TEXT] {5}\nHello)"

        let bodies = IMAPResponseParser.parseBodyResponses([response])
        #expect(bodies.count == 1)
        #expect(bodies[0].attachments.isEmpty)
    }

    // MARK: - Folder Name Extraction

    @Test("Extracts folder name from [Gmail]/Sent Mail path")
    func folderNameFromGmailPath() {
        let line = #"* LIST (\Sent) "/" "[Gmail]/Sent Mail""#
        let result = IMAPResponseParser.parseListResponse(line)
        #expect(result?.name == "Sent Mail")
    }

    @Test("Extracts folder name from nested path")
    func folderNameFromNestedPath() {
        let line = #"* LIST () "/" "Work/Projects/Alpha""#
        let result = IMAPResponseParser.parseListResponse(line)
        #expect(result?.name == "Alpha")
    }

    @Test("Folder name equals path for top-level folder")
    func folderNameTopLevel() {
        let line = #"* LIST () "/" "INBOX""#
        let result = IMAPResponseParser.parseListResponse(line)
        #expect(result?.name == "INBOX")
    }

    // MARK: - Date Parsing

    @Test("Parses RFC 2822 date with day name")
    func parseDateRFC2822() {
        let response = """
        * 1 FETCH (UID 101 FLAGS () RFC822.SIZE 100 BODY[HEADER.FIELDS (DATE)] {40}
        Date: Mon, 1 Jan 2024 12:00:00 +0000

        """

        let headers = IMAPResponseParser.parseHeaderResponses([response])
        #expect(headers.count == 1)
        #expect(headers[0].date != nil)

        // Verify the parsed date components
        if let date = headers[0].date {
            let calendar = Calendar(identifier: .gregorian)
            let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
            #expect(components.year == 2024)
            #expect(components.month == 1)
            #expect(components.day == 1)
        }
    }

    @Test("Parses date without day name")
    func parseDateWithoutDayName() {
        let response = """
        * 1 FETCH (UID 101 FLAGS () RFC822.SIZE 100 BODY[HEADER.FIELDS (DATE)] {30}
        Date: 1 Jan 2024 12:00:00 +0000

        """

        let headers = IMAPResponseParser.parseHeaderResponses([response])
        #expect(headers.count == 1)
        #expect(headers[0].date != nil)
    }

    @Test("Returns nil date for missing Date header")
    func parseDateMissing() {
        let response = "* 1 FETCH (UID 101 FLAGS () RFC822.SIZE 100)"

        let headers = IMAPResponseParser.parseHeaderResponses([response])
        #expect(headers.count == 1)
        #expect(headers[0].date == nil)
    }

    // MARK: - Address List Parsing

    @Test("Parses single address in To field")
    func parseAddressSingle() {
        let response = """
        * 1 FETCH (UID 101 FLAGS () RFC822.SIZE 100 BODY[HEADER.FIELDS (TO)] {25}
        To: user@example.com

        """

        let headers = IMAPResponseParser.parseHeaderResponses([response])
        #expect(headers[0].to == ["user@example.com"])
    }

    @Test("Parses multiple comma-separated addresses")
    func parseAddressMultiple() {
        let response = """
        * 1 FETCH (UID 101 FLAGS () RFC822.SIZE 100 BODY[HEADER.FIELDS (TO)] {60}
        To: user1@test.com, user2@test.com, user3@test.com

        """

        let headers = IMAPResponseParser.parseHeaderResponses([response])
        #expect(headers[0].to.count == 3)
    }

    @Test("Returns empty array for missing To field")
    func parseAddressMissing() {
        let response = "* 1 FETCH (UID 101 FLAGS () RFC822.SIZE 100)"

        let headers = IMAPResponseParser.parseHeaderResponses([response])
        #expect(headers[0].to.isEmpty)
        #expect(headers[0].cc.isEmpty)
        #expect(headers[0].bcc.isEmpty)
    }

    // MARK: - Multi-UID BODYSTRUCTURE Parsing (N+1 fix)

    @Test("Parses multiple UID BODYSTRUCTUREs in one batch (N+1 fix)")
    func parseMultiBodyStructures() {
        let responses = [
            #"* 1 FETCH (UID 101 BODYSTRUCTURE ("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" 100 5))"#,
            #"* 2 FETCH (UID 102 BODYSTRUCTURE (("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" 100 5)("TEXT" "HTML" ("CHARSET" "UTF-8") NIL NIL "QUOTED-PRINTABLE" 500 20) "ALTERNATIVE"))"#,
            "TAG1 OK FETCH completed",
        ]

        let result = IMAPResponseParser.parseMultiBodyStructures(from: responses)

        #expect(result.count == 2)
        #expect(result[101]?.count == 1)
        #expect(result[101]?[0].mimeType == "text/plain")
        #expect(result[102]?.count == 2)

        let plainPart = result[102]?.first { $0.mimeType == "text/plain" }
        let htmlPart = result[102]?.first { $0.mimeType == "text/html" }
        #expect(plainPart != nil)
        #expect(htmlPart != nil)
    }

    @Test("parseMultiBodyStructures ignores non-BODYSTRUCTURE responses")
    func parseMultiBodyStructuresIgnoresOther() {
        let responses = [
            "* 1 FETCH (UID 101 FLAGS (\\Seen))",
            "TAG1 OK completed",
        ]

        let result = IMAPResponseParser.parseMultiBodyStructures(from: responses)
        #expect(result.isEmpty)
    }

    @Test("parseMultiBodyStructures returns empty for empty input")
    func parseMultiBodyStructuresEmpty() {
        let result = IMAPResponseParser.parseMultiBodyStructures(from: [])
        #expect(result.isEmpty)
    }

    @Test("parseMultiBodyStructures skips responses with UID 0")
    func parseMultiBodyStructuresSkipsUID0() {
        // A response without a valid UID value
        let responses = [
            #"* 1 FETCH (BODYSTRUCTURE ("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" 100 5))"#,
        ]

        let result = IMAPResponseParser.parseMultiBodyStructures(from: responses)
        #expect(result.isEmpty) // UID 0 is filtered out
    }

    // MARK: - Body Parts By Section (N+1 fix)

    @Test("Extracts body content keyed by section number")
    func extractBodyPartsBySection() {
        let response = "* 1 FETCH (UID 101 BODY[1] {5}\nHello)"

        let parts = IMAPResponseParser.extractBodyPartsBySection(from: response)

        #expect(parts.count == 1)
        #expect(parts["1"] != nil)
        #expect(parts["1"]?.contains("Hello") == true)
    }

    @Test("extractBodyPartsBySection handles TEXT section")
    func extractBodyPartsBySectionText() {
        let response = "* 1 FETCH (UID 101 BODY[TEXT] {11}\nPlain text.)"

        let parts = IMAPResponseParser.extractBodyPartsBySection(from: response)

        #expect(parts["TEXT"] != nil)
        #expect(parts["TEXT"]?.contains("Plain text") == true)
    }

    @Test("extractBodyPartsBySection skips HEADER sections")
    func extractBodyPartsBySectionSkipsHeaders() {
        let response = "* 1 FETCH (UID 101 BODY[HEADER.FIELDS (FROM)] {20}\nFrom: test@test.com)"

        let parts = IMAPResponseParser.extractBodyPartsBySection(from: response)
        #expect(parts.isEmpty) // HEADER sections should be skipped
    }

    @Test("extractBodyPartsBySection skips NIL content")
    func extractBodyPartsBySectionSkipsNIL() {
        let response = "* 1 FETCH (UID 101 BODY[1] NIL)"

        let parts = IMAPResponseParser.extractBodyPartsBySection(from: response)
        #expect(parts.isEmpty)
    }

    @Test("extractBodyPartsBySection returns empty for non-BODY response")
    func extractBodyPartsBySectionNonBody() {
        let response = "* 1 FETCH (UID 101 FLAGS (\\Seen))"

        let parts = IMAPResponseParser.extractBodyPartsBySection(from: response)
        #expect(parts.isEmpty)
    }

    // MARK: - Edge Cases

    @Test("Handles empty response arrays gracefully")
    func edgeCaseEmptyArrays() {
        #expect(IMAPResponseParser.parseSearchResponse(from: []).isEmpty)
        #expect(IMAPResponseParser.parseHeaderResponses([]).isEmpty)
        #expect(IMAPResponseParser.parseBodyResponses([]).isEmpty)
        #expect(IMAPResponseParser.parseFlagResponses([]).isEmpty)
        #expect(IMAPResponseParser.parseUIDValidity(from: []) == 0)
        #expect(IMAPResponseParser.parseExists(from: []) == 0)
    }

    @Test("Handles responses with only whitespace")
    func edgeCaseWhitespace() {
        let responses = ["   ", "\t", "\n"]
        #expect(IMAPResponseParser.parseSearchResponse(from: responses).isEmpty)
        #expect(IMAPResponseParser.parseHeaderResponses(responses).isEmpty)
    }

    @Test("BODYSTRUCTURE parsing handles missing parentheses")
    func edgeCaseMalformedBodyStructure() {
        let response = "* 1 FETCH (UID 101 BODYSTRUCTURE )"
        let parts = IMAPResponseParser.parseBodyStructure(from: response)
        #expect(parts.isEmpty)
    }

    @Test("Flag parsing correctly handles UID 0 (skips it)")
    func edgeCaseUIDZeroFlags() {
        // A response without a valid UID should result in UID 0 which is skipped
        let responses = ["* 1 FETCH (FLAGS (\\Seen))"]
        let flags = IMAPResponseParser.parseFlagResponses(responses)
        #expect(flags.isEmpty) // UID 0 is filtered out
    }

    // MARK: - IMAP Literal Length Parsing

    @Test("extractBodyPartsBySection respects literal length and does not include trailing data")
    func extractBodyPartsRespectsLiteralLength() {
        // Simulates a multi-part FETCH response where BODY[1] and BODY[2] are
        // adjacent. The parser must use {NNN} to extract exactly N bytes for
        // section 1, not everything to end of string.
        let response = "* 1 FETCH (UID 101 BODY[1] {11}\nPlain text. BODY[2] {27}\n<html><b>Bold</b></html>)"

        let parts = IMAPResponseParser.extractBodyPartsBySection(from: response)

        #expect(parts["1"] != nil)
        #expect(parts["2"] != nil)

        // Section 1 should contain ONLY the plain text, not the BODY[2] data
        if let plainContent = parts["1"] {
            #expect(!plainContent.contains("BODY[2]"), "Section 1 should not contain BODY[2] framing")
            #expect(!plainContent.contains("<html>"), "Section 1 should not contain HTML from section 2")
            #expect(plainContent.contains("Plain text"), "Section 1 should contain the plain text content")
        }

        // Section 2 should contain the HTML content
        if let htmlContent = parts["2"] {
            #expect(htmlContent.contains("<html>"), "Section 2 should contain HTML")
            #expect(htmlContent.contains("Bold"), "Section 2 should contain Bold text")
        }
    }

    @Test("extractBodyPartsBySection handles response with BODY[1] followed by protocol framing")
    func extractBodyPartsDoesNotIncludeProtocolFraming() {
        // This simulates the exact bug: raw IMAP framing like "BODY[1] {8609}"
        // appearing in the rendered email body
        let plainText = "Hello, this is a test email."
        let response = "* 1 FETCH (UID 200 BODY[1] {\(plainText.utf8.count)}\n\(plainText))"

        let parts = IMAPResponseParser.extractBodyPartsBySection(from: response)

        #expect(parts["1"] == plainText)
    }

    @Test("extractBodyPartsBySection handles zero-length literal")
    func extractBodyPartsZeroLengthLiteral() {
        let response = "* 1 FETCH (UID 101 BODY[1] {0}\n)"

        let parts = IMAPResponseParser.extractBodyPartsBySection(from: response)
        // Zero-length content should result in nil or empty
        #expect(parts["1"] == nil || parts["1"]?.isEmpty == true)
    }

    @Test("Fallback extraction stops at next BODY[ marker when no literal length")
    func fallbackExtractionStopsAtNextBody() {
        // Some servers might not use literal length format;
        // the fallback should still stop at the next BODY[ marker
        let response = "* 1 FETCH (UID 101 BODY[1] \nPlain content here\n BODY[2] \n<html>HTML</html>)"

        let parts = IMAPResponseParser.extractBodyPartsBySection(from: response)

        if let plain = parts["1"] {
            #expect(!plain.contains("<html>"), "Fallback extraction should stop at BODY[2]")
            #expect(plain.contains("Plain content"), "Should contain the plain text")
        }
    }
}
