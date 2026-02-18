import Foundation
import Testing
@testable import VaultMailFeature

/// Tests for ProviderFolderMapper — the universal 3-tier folder mapping system.
///
/// Validates RFC 6154 attribute mapping, provider-specific paths,
/// name heuristics, and shouldSync logic across all providers.
///
/// Spec ref: FR-MPROV-11 (Provider-Agnostic Folder Mapping)
@Suite("ProviderFolderMapper — FR-MPROV-11")
struct ProviderFolderMapperTests {

    // MARK: - Tier 1: RFC 6154 Attributes (Universal)

    @Test("INBOX path maps to .inbox")
    func inboxPath() {
        let type = ProviderFolderMapper.folderType(imapPath: "INBOX", attributes: [])
        #expect(type == .inbox)
    }

    @Test("\\Inbox attribute maps to .inbox")
    func inboxAttribute() {
        let type = ProviderFolderMapper.folderType(imapPath: "Something", attributes: ["\\Inbox"])
        #expect(type == .inbox)
    }

    @Test("\\Sent attribute maps to .sent")
    func sentAttribute() {
        let type = ProviderFolderMapper.folderType(imapPath: "Anything", attributes: ["\\Sent"])
        #expect(type == .sent)
    }

    @Test("\\Drafts attribute maps to .drafts")
    func draftsAttribute() {
        let type = ProviderFolderMapper.folderType(imapPath: "Anything", attributes: ["\\Drafts"])
        #expect(type == .drafts)
    }

    @Test("\\Trash attribute maps to .trash")
    func trashAttribute() {
        let type = ProviderFolderMapper.folderType(imapPath: "Anything", attributes: ["\\Trash"])
        #expect(type == .trash)
    }

    @Test("\\Junk attribute maps to .spam")
    func junkAttribute() {
        let type = ProviderFolderMapper.folderType(imapPath: "Anything", attributes: ["\\Junk"])
        #expect(type == .spam)
    }

    @Test("\\Flagged attribute maps to .starred")
    func flaggedAttribute() {
        let type = ProviderFolderMapper.folderType(imapPath: "Anything", attributes: ["\\Flagged"])
        #expect(type == .starred)
    }

    @Test("\\All attribute maps to .archive")
    func allAttribute() {
        let type = ProviderFolderMapper.folderType(imapPath: "Anything", attributes: ["\\All"])
        #expect(type == .archive)
    }

    @Test("\\Archive attribute maps to .archive")
    func archiveAttribute() {
        let type = ProviderFolderMapper.folderType(imapPath: "Anything", attributes: ["\\Archive"])
        #expect(type == .archive)
    }

    @Test("Attributes are case-insensitive")
    func attributeCaseInsensitive() {
        let type = ProviderFolderMapper.folderType(imapPath: "Anything", attributes: ["\\SENT"])
        #expect(type == .sent)
    }

    // MARK: - Tier 2: Provider-Specific Paths

    @Test("Gmail: [Gmail]/Sent Mail maps to .sent")
    func gmailSentPath() {
        let type = ProviderFolderMapper.folderType(imapPath: "[Gmail]/Sent Mail", attributes: [], provider: .gmail)
        #expect(type == .sent)
    }

    @Test("Gmail: [Gmail]/Trash maps to .trash")
    func gmailTrashPath() {
        let type = ProviderFolderMapper.folderType(imapPath: "[Gmail]/Trash", attributes: [], provider: .gmail)
        #expect(type == .trash)
    }

    @Test("Gmail: [Gmail]/Spam maps to .spam")
    func gmailSpamPath() {
        let type = ProviderFolderMapper.folderType(imapPath: "[Gmail]/Spam", attributes: [], provider: .gmail)
        #expect(type == .spam)
    }

    @Test("Outlook: Sent Items maps to .sent")
    func outlookSentPath() {
        let type = ProviderFolderMapper.folderType(imapPath: "Sent Items", attributes: [], provider: .outlook)
        #expect(type == .sent)
    }

    @Test("Outlook: Deleted Items maps to .trash")
    func outlookTrashPath() {
        let type = ProviderFolderMapper.folderType(imapPath: "Deleted Items", attributes: [], provider: .outlook)
        #expect(type == .trash)
    }

    @Test("Outlook: Junk Email maps to .spam")
    func outlookSpamPath() {
        let type = ProviderFolderMapper.folderType(imapPath: "Junk Email", attributes: [], provider: .outlook)
        #expect(type == .spam)
    }

    @Test("Yahoo: Sent maps to .sent")
    func yahooSentPath() {
        let type = ProviderFolderMapper.folderType(imapPath: "Sent", attributes: [], provider: .yahoo)
        #expect(type == .sent)
    }

    @Test("Yahoo: Draft maps to .drafts")
    func yahooDraftPath() {
        let type = ProviderFolderMapper.folderType(imapPath: "Draft", attributes: [], provider: .yahoo)
        #expect(type == .drafts)
    }

    @Test("Yahoo: Bulk Mail maps to .spam")
    func yahooBulkMailPath() {
        let type = ProviderFolderMapper.folderType(imapPath: "Bulk Mail", attributes: [], provider: .yahoo)
        #expect(type == .spam)
    }

    @Test("iCloud: Sent Messages maps to .sent")
    func icloudSentPath() {
        let type = ProviderFolderMapper.folderType(imapPath: "Sent Messages", attributes: [], provider: .icloud)
        #expect(type == .sent)
    }

    @Test("iCloud: Deleted Messages maps to .trash")
    func icloudTrashPath() {
        let type = ProviderFolderMapper.folderType(imapPath: "Deleted Messages", attributes: [], provider: .icloud)
        #expect(type == .trash)
    }

    @Test("iCloud: Junk maps to .spam")
    func icloudJunkPath() {
        let type = ProviderFolderMapper.folderType(imapPath: "Junk", attributes: [], provider: .icloud)
        #expect(type == .spam)
    }

    // MARK: - Tier 3: Name Heuristics

    @Test("Heuristic: folder containing 'sent' maps to .sent")
    func heuristicSent() {
        let type = ProviderFolderMapper.folderType(imapPath: "Sent Items", attributes: [], provider: .custom)
        #expect(type == .sent)
    }

    @Test("Heuristic: folder containing 'draft' maps to .drafts")
    func heuristicDrafts() {
        let type = ProviderFolderMapper.folderType(imapPath: "My Drafts", attributes: [], provider: .custom)
        #expect(type == .drafts)
    }

    @Test("Heuristic: folder containing 'trash' maps to .trash")
    func heuristicTrash() {
        let type = ProviderFolderMapper.folderType(imapPath: "Trash Bin", attributes: [], provider: .custom)
        #expect(type == .trash)
    }

    @Test("Heuristic: folder containing 'deleted' maps to .trash")
    func heuristicDeleted() {
        let type = ProviderFolderMapper.folderType(imapPath: "Deleted Items", attributes: [], provider: .custom)
        #expect(type == .trash)
    }

    @Test("Heuristic: folder containing 'spam' maps to .spam")
    func heuristicSpam() {
        let type = ProviderFolderMapper.folderType(imapPath: "Spam Filter", attributes: [], provider: .custom)
        #expect(type == .spam)
    }

    @Test("Heuristic: folder containing 'junk' maps to .spam")
    func heuristicJunk() {
        let type = ProviderFolderMapper.folderType(imapPath: "Junk Mail", attributes: [], provider: .custom)
        #expect(type == .spam)
    }

    @Test("Heuristic: folder containing 'archive' maps to .archive")
    func heuristicArchive() {
        let type = ProviderFolderMapper.folderType(imapPath: "Archive", attributes: [], provider: .custom)
        #expect(type == .archive)
    }

    @Test("Heuristic: nested folder extracts final component")
    func heuristicNestedFolder() {
        let type = ProviderFolderMapper.folderType(imapPath: "INBOX/Sent Items", attributes: [], provider: .custom)
        #expect(type == .sent)
    }

    @Test("Unknown folder falls back to .custom")
    func unknownFolder() {
        let type = ProviderFolderMapper.folderType(imapPath: "Personal/Projects", attributes: [], provider: .custom)
        #expect(type == .custom)
    }

    // MARK: - Attribute Priority Over Path

    @Test("RFC 6154 attribute takes priority over provider path")
    func attributePriorityOverPath() {
        // Even though the path is unknown, the attribute should win
        let type = ProviderFolderMapper.folderType(
            imapPath: "Random Folder",
            attributes: ["\\Sent"],
            provider: .custom
        )
        #expect(type == .sent)
    }

    // MARK: - shouldSync

    @Test("\\Noselect folder should not sync")
    func noselectNotSynced() {
        let sync = ProviderFolderMapper.shouldSync(imapPath: "Anything", attributes: ["\\Noselect"])
        #expect(!sync)
    }

    @Test("\\All folder should not sync")
    func allNotSynced() {
        let sync = ProviderFolderMapper.shouldSync(imapPath: "[Gmail]/All Mail", attributes: ["\\All"])
        #expect(!sync)
    }

    @Test("\\Important folder should not sync")
    func importantNotSynced() {
        let sync = ProviderFolderMapper.shouldSync(imapPath: "Important", attributes: ["\\Important"])
        #expect(!sync)
    }

    @Test("Gmail: [Gmail]/Important should not sync even without attribute")
    func gmailImportantPathNotSynced() {
        let sync = ProviderFolderMapper.shouldSync(
            imapPath: "[Gmail]/Important",
            attributes: [],
            provider: .gmail
        )
        #expect(!sync)
    }

    @Test("Regular folder should sync")
    func regularFolderSynced() {
        let sync = ProviderFolderMapper.shouldSync(imapPath: "INBOX", attributes: ["\\Inbox"])
        #expect(sync)
    }

    @Test("Yahoo: Bulk Mail should sync (it's the spam folder, not skipped)")
    func yahooBulkMailSynced() {
        let sync = ProviderFolderMapper.shouldSync(
            imapPath: "Bulk Mail",
            attributes: [],
            provider: .yahoo
        )
        #expect(sync)
    }

    @Test("Custom folder should sync")
    func customFolderSynced() {
        let sync = ProviderFolderMapper.shouldSync(
            imapPath: "Work/Projects",
            attributes: [],
            provider: .custom
        )
        #expect(sync)
    }
}
