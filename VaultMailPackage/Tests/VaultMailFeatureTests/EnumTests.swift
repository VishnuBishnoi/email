import Foundation
import Testing
@testable import VaultMailFeature

/// Verify all enum raw values and counts match Foundation spec Section 5.
@Suite("Enum Definitions")
struct EnumTests {

    // MARK: - AICategory (Section 5.2)

    @Test("AICategory has 6 cases per spec Section 5.2")
    func aiCategoryCount() {
        #expect(AICategory.allCases.count == 6)
    }

    @Test("AICategory raw values match spec")
    func aiCategoryRawValues() {
        #expect(AICategory.primary.rawValue == "primary")
        #expect(AICategory.social.rawValue == "social")
        #expect(AICategory.promotions.rawValue == "promotions")
        #expect(AICategory.updates.rawValue == "updates")
        #expect(AICategory.forums.rawValue == "forums")
        #expect(AICategory.uncategorized.rawValue == "uncategorized")
    }

    @Test("AICategory round-trips through Codable")
    func aiCategoryCodable() throws {
        let original = AICategory.promotions
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AICategory.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - FolderType (Section 5.3)

    @Test("FolderType has 8 cases per spec Section 5.3")
    func folderTypeCount() {
        #expect(FolderType.allCases.count == 8)
    }

    @Test("FolderType raw values match spec")
    func folderTypeRawValues() {
        #expect(FolderType.inbox.rawValue == "inbox")
        #expect(FolderType.sent.rawValue == "sent")
        #expect(FolderType.drafts.rawValue == "drafts")
        #expect(FolderType.trash.rawValue == "trash")
        #expect(FolderType.spam.rawValue == "spam")
        #expect(FolderType.archive.rawValue == "archive")
        #expect(FolderType.starred.rawValue == "starred")
        #expect(FolderType.custom.rawValue == "custom")
    }

    @Test("FolderType round-trips through Codable")
    func folderTypeCodable() throws {
        let original = FolderType.archive
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FolderType.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - SendState (Section 5.5)

    @Test("SendState has 5 cases per spec Section 5.5")
    func sendStateCount() {
        #expect(SendState.allCases.count == 5)
    }

    @Test("SendState raw values match spec")
    func sendStateRawValues() {
        #expect(SendState.none.rawValue == "none")
        #expect(SendState.queued.rawValue == "queued")
        #expect(SendState.sending.rawValue == "sending")
        #expect(SendState.failed.rawValue == "failed")
        #expect(SendState.sent.rawValue == "sent")
    }

    @Test("SendState round-trips through Codable")
    func sendStateCodable() throws {
        let original = SendState.queued
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SendState.self, from: data)
        #expect(decoded == original)
    }
}
