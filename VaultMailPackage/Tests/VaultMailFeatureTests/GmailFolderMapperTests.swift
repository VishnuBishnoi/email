import Foundation
import Testing
@testable import VaultMailFeature

/// Tests for Gmail folder mapping logic.
///
/// Validates that Gmail IMAP folder attributes and paths are correctly
/// mapped to our FolderType enum, and that sync eligibility is determined
/// correctly per the spec.
///
/// Spec ref: Email Sync spec FR-SYNC-01 step 1 (Folder discovery)
@Suite("Gmail Folder Mapper — FR-SYNC-01")
struct GmailFolderMapperTests {

    // MARK: - Folder Type Mapping (FR-SYNC-01 step 1)

    @Test("\\Inbox attribute maps to .inbox")
    func inboxByAttribute() {
        let result = GmailFolderMapper.folderType(
            imapPath: "INBOX",
            attributes: ["\\Inbox"]
        )
        #expect(result == .inbox)
    }

    @Test("INBOX path maps to .inbox even without attribute")
    func inboxByPath() {
        let result = GmailFolderMapper.folderType(
            imapPath: "INBOX",
            attributes: []
        )
        #expect(result == .inbox)
    }

    @Test("\\Sent attribute maps to .sent")
    func sentByAttribute() {
        let result = GmailFolderMapper.folderType(
            imapPath: "[Gmail]/Sent Mail",
            attributes: ["\\Sent"]
        )
        #expect(result == .sent)
    }

    @Test("[Gmail]/Sent Mail path maps to .sent without attribute")
    func sentByPath() {
        let result = GmailFolderMapper.folderType(
            imapPath: "[Gmail]/Sent Mail",
            attributes: []
        )
        #expect(result == .sent)
    }

    @Test("\\Drafts attribute maps to .drafts")
    func draftsByAttribute() {
        let result = GmailFolderMapper.folderType(
            imapPath: "[Gmail]/Drafts",
            attributes: ["\\Drafts"]
        )
        #expect(result == .drafts)
    }

    @Test("[Gmail]/Drafts path maps to .drafts without attribute")
    func draftsByPath() {
        let result = GmailFolderMapper.folderType(
            imapPath: "[Gmail]/Drafts",
            attributes: []
        )
        #expect(result == .drafts)
    }

    @Test("\\Trash attribute maps to .trash")
    func trashByAttribute() {
        let result = GmailFolderMapper.folderType(
            imapPath: "[Gmail]/Trash",
            attributes: ["\\Trash"]
        )
        #expect(result == .trash)
    }

    @Test("[Gmail]/Trash path maps to .trash without attribute")
    func trashByPath() {
        let result = GmailFolderMapper.folderType(
            imapPath: "[Gmail]/Trash",
            attributes: []
        )
        #expect(result == .trash)
    }

    @Test("\\Junk attribute maps to .spam (FR-SYNC-01: Gmail Spam)")
    func spamByAttribute() {
        let result = GmailFolderMapper.folderType(
            imapPath: "[Gmail]/Spam",
            attributes: ["\\Junk"]
        )
        #expect(result == .spam)
    }

    @Test("[Gmail]/Spam path maps to .spam without attribute")
    func spamByPath() {
        let result = GmailFolderMapper.folderType(
            imapPath: "[Gmail]/Spam",
            attributes: []
        )
        #expect(result == .spam)
    }

    @Test("\\Flagged attribute maps to .starred")
    func starredByAttribute() {
        let result = GmailFolderMapper.folderType(
            imapPath: "[Gmail]/Starred",
            attributes: ["\\Flagged"]
        )
        #expect(result == .starred)
    }

    @Test("[Gmail]/Starred path maps to .starred without attribute")
    func starredByPath() {
        let result = GmailFolderMapper.folderType(
            imapPath: "[Gmail]/Starred",
            attributes: []
        )
        #expect(result == .starred)
    }

    @Test("\\All attribute maps to .archive")
    func allMailByAttribute() {
        let result = GmailFolderMapper.folderType(
            imapPath: "[Gmail]/All Mail",
            attributes: ["\\All"]
        )
        #expect(result == .archive)
    }

    @Test("[Gmail]/All Mail path maps to .archive without attribute")
    func allMailByPath() {
        let result = GmailFolderMapper.folderType(
            imapPath: "[Gmail]/All Mail",
            attributes: []
        )
        #expect(result == .archive)
    }

    @Test("User-created label maps to .custom")
    func customLabel() {
        let result = GmailFolderMapper.folderType(
            imapPath: "Work/Projects",
            attributes: []
        )
        #expect(result == .custom)
    }

    @Test("Attribute matching is case-insensitive")
    func caseInsensitiveAttributes() {
        let inbox = GmailFolderMapper.folderType(imapPath: "INBOX", attributes: ["\\INBOX"])
        #expect(inbox == .inbox)

        let sent = GmailFolderMapper.folderType(imapPath: "[Gmail]/Sent Mail", attributes: ["\\SENT"])
        #expect(sent == .sent)

        let junk = GmailFolderMapper.folderType(imapPath: "[Gmail]/Spam", attributes: ["\\JUNK"])
        #expect(junk == .spam)
    }

    @Test("Multiple attributes are handled correctly")
    func multipleAttributes() {
        // Gmail folders often have multiple attributes like \\HasNoChildren
        let result = GmailFolderMapper.folderType(
            imapPath: "[Gmail]/Sent Mail",
            attributes: ["\\Sent", "\\HasNoChildren"]
        )
        #expect(result == .sent)
    }

    // MARK: - Sync Eligibility (FR-SYNC-01)

    @Test("[Gmail]/All Mail MUST NOT be synced (FR-SYNC-01)")
    func allMailNotSynced() {
        let shouldSync = GmailFolderMapper.shouldSync(
            imapPath: "[Gmail]/All Mail",
            attributes: ["\\All", "\\HasNoChildren"]
        )
        #expect(!shouldSync)
    }

    @Test("[Gmail]/All Mail not synced by path even without \\All attribute")
    func allMailNotSyncedByPath() {
        let shouldSync = GmailFolderMapper.shouldSync(
            imapPath: "[Gmail]/All Mail",
            attributes: []
        )
        #expect(!shouldSync)
    }

    @Test("[Gmail]/Important MUST NOT be synced (FR-SYNC-01)")
    func importantNotSynced() {
        let shouldSync = GmailFolderMapper.shouldSync(
            imapPath: "[Gmail]/Important",
            attributes: ["\\Important"]
        )
        #expect(!shouldSync)
    }

    @Test("\\Important attribute MUST NOT be synced regardless of path (FR-SYNC-01)")
    func importantAttributeNotSynced() {
        // FR-SYNC-01: \Important → MUST NOT be synced as a folder;
        // importance is a flag, not a mailbox.
        // This must work by attribute, not just by path.
        let shouldSync = GmailFolderMapper.shouldSync(
            imapPath: "SomeOtherFolder",
            attributes: ["\\Important"]
        )
        #expect(!shouldSync)
    }

    @Test("\\Important attribute check is case-insensitive")
    func importantCaseInsensitive() {
        let shouldSync = GmailFolderMapper.shouldSync(
            imapPath: "AnyFolder",
            attributes: ["\\IMPORTANT"]
        )
        #expect(!shouldSync)
    }

    @Test("Folder with \\Noselect MUST NOT be synced")
    func noselectNotSynced() {
        let shouldSync = GmailFolderMapper.shouldSync(
            imapPath: "[Gmail]",
            attributes: ["\\Noselect", "\\HasChildren"]
        )
        #expect(!shouldSync)
    }

    @Test("\\Noselect check is case-insensitive")
    func noselectCaseInsensitive() {
        let shouldSync = GmailFolderMapper.shouldSync(
            imapPath: "SomeFolder",
            attributes: ["\\NOSELECT"]
        )
        #expect(!shouldSync)
    }

    @Test("INBOX SHOULD be synced")
    func inboxSynced() {
        let shouldSync = GmailFolderMapper.shouldSync(
            imapPath: "INBOX",
            attributes: ["\\Inbox"]
        )
        #expect(shouldSync)
    }

    @Test("Sent Mail SHOULD be synced")
    func sentSynced() {
        let shouldSync = GmailFolderMapper.shouldSync(
            imapPath: "[Gmail]/Sent Mail",
            attributes: ["\\Sent"]
        )
        #expect(shouldSync)
    }

    @Test("Drafts SHOULD be synced")
    func draftsSynced() {
        let shouldSync = GmailFolderMapper.shouldSync(
            imapPath: "[Gmail]/Drafts",
            attributes: ["\\Drafts"]
        )
        #expect(shouldSync)
    }

    @Test("Trash SHOULD be synced")
    func trashSynced() {
        let shouldSync = GmailFolderMapper.shouldSync(
            imapPath: "[Gmail]/Trash",
            attributes: ["\\Trash"]
        )
        #expect(shouldSync)
    }

    @Test("Spam SHOULD be synced")
    func spamSynced() {
        let shouldSync = GmailFolderMapper.shouldSync(
            imapPath: "[Gmail]/Spam",
            attributes: ["\\Junk"]
        )
        #expect(shouldSync)
    }

    @Test("Starred SHOULD be synced")
    func starredSynced() {
        let shouldSync = GmailFolderMapper.shouldSync(
            imapPath: "[Gmail]/Starred",
            attributes: ["\\Flagged"]
        )
        #expect(shouldSync)
    }

    @Test("Custom labels SHOULD be synced")
    func customLabelsSynced() {
        let shouldSync = GmailFolderMapper.shouldSync(
            imapPath: "Work/Projects",
            attributes: []
        )
        #expect(shouldSync)
    }

    // MARK: - Integration: Full Folder List Filtering

    @Test("Full Gmail folder list correctly filters syncable folders")
    func fullFolderListFiltering() {
        let gmailFolders: [(path: String, attrs: [String])] = [
            ("INBOX", ["\\Inbox"]),
            ("[Gmail]", ["\\Noselect", "\\HasChildren"]),
            ("[Gmail]/All Mail", ["\\All", "\\HasNoChildren"]),
            ("[Gmail]/Drafts", ["\\Drafts", "\\HasNoChildren"]),
            ("[Gmail]/Important", ["\\Important", "\\HasNoChildren"]),
            ("[Gmail]/Sent Mail", ["\\Sent", "\\HasNoChildren"]),
            ("[Gmail]/Spam", ["\\Junk", "\\HasNoChildren"]),
            ("[Gmail]/Starred", ["\\Flagged", "\\HasNoChildren"]),
            ("[Gmail]/Trash", ["\\Trash", "\\HasNoChildren"]),
            ("Work", []),
            ("Personal", []),
        ]

        let syncable = gmailFolders.filter {
            GmailFolderMapper.shouldSync(imapPath: $0.path, attributes: $0.attrs)
        }

        // Should exclude: [Gmail] (Noselect), All Mail (\All), Important
        #expect(syncable.count == 8)

        let syncablePaths = syncable.map(\.path)
        #expect(syncablePaths.contains("INBOX"))
        #expect(syncablePaths.contains("[Gmail]/Drafts"))
        #expect(syncablePaths.contains("[Gmail]/Sent Mail"))
        #expect(syncablePaths.contains("[Gmail]/Spam"))
        #expect(syncablePaths.contains("[Gmail]/Starred"))
        #expect(syncablePaths.contains("[Gmail]/Trash"))
        #expect(syncablePaths.contains("Work"))
        #expect(syncablePaths.contains("Personal"))

        // Must NOT contain these
        #expect(!syncablePaths.contains("[Gmail]"))
        #expect(!syncablePaths.contains("[Gmail]/All Mail"))
        #expect(!syncablePaths.contains("[Gmail]/Important"))
    }

    @Test("Folder types are correctly assigned for full Gmail list")
    func fullFolderListTypes() {
        let testCases: [(path: String, attrs: [String], expected: FolderType)] = [
            ("INBOX", ["\\Inbox"], .inbox),
            ("[Gmail]/Sent Mail", ["\\Sent"], .sent),
            ("[Gmail]/Drafts", ["\\Drafts"], .drafts),
            ("[Gmail]/Trash", ["\\Trash"], .trash),
            ("[Gmail]/Spam", ["\\Junk"], .spam),
            ("[Gmail]/Starred", ["\\Flagged"], .starred),
            ("[Gmail]/All Mail", ["\\All"], .archive),
            ("Work", [], .custom),
            ("Personal/Finance", [], .custom),
        ]

        for testCase in testCases {
            let result = GmailFolderMapper.folderType(
                imapPath: testCase.path,
                attributes: testCase.attrs
            )
            #expect(
                result == testCase.expected,
                "Expected \(testCase.path) to be \(testCase.expected), got \(result)"
            )
        }
    }
}
