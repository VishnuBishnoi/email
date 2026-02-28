#if os(macOS)
import Testing
@testable import VaultMailFeature

@Suite("MacOSMainView Pagination Rules")
struct MacOSMainViewPaginationTests {
    @Test("TC-MAC-PAG-01: sentinel shows when hasMorePages is true")
    func sentinelWhenHasMorePages() {
        #expect(
            MacPaginationRuleEngine.shouldShowSentinel(
                hasMorePages: true,
                isCatchUpEligibleContext: false,
                reachedServerHistoryBoundary: true
            )
        )
    }

    @Test("TC-MAC-PAG-02: catch-up allowed in eligible folder context")
    func catchUpAllowedInEligibleContext() {
        #expect(
            MacPaginationRuleEngine.shouldAttemptCatchUp(
                hasMorePages: false,
                isUnifiedMode: false,
                isSearchActive: false,
                hasSelectedFolder: true,
                isOutboxSelected: false,
                folderType: FolderType.inbox.rawValue,
                folderImapPath: "INBOX"
            )
        )
    }

    @Test("TC-MAC-PAG-05: Unified mode blocks catch-up")
    func unifiedModeBlocksCatchUp() {
        #expect(
            !MacPaginationRuleEngine.shouldAttemptCatchUp(
                hasMorePages: false,
                isUnifiedMode: true,
                isSearchActive: false,
                hasSelectedFolder: true,
                isOutboxSelected: false,
                folderType: FolderType.inbox.rawValue,
                folderImapPath: "INBOX"
            )
        )
    }

    @Test("missing selected folder blocks catch-up")
    func noSelectedFolderBlocksCatchUp() {
        #expect(
            !MacPaginationRuleEngine.shouldAttemptCatchUp(
                hasMorePages: false,
                isUnifiedMode: false,
                isSearchActive: false,
                hasSelectedFolder: false,
                isOutboxSelected: false,
                folderType: nil,
                folderImapPath: nil
            )
        )
    }

    @Test("TC-MAC-PAG-06: active search blocks catch-up")
    func activeSearchBlocksCatchUp() {
        #expect(
            !MacPaginationRuleEngine.shouldAttemptCatchUp(
                hasMorePages: false,
                isUnifiedMode: false,
                isSearchActive: true,
                hasSelectedFolder: true,
                isOutboxSelected: false,
                folderType: FolderType.inbox.rawValue,
                folderImapPath: "INBOX"
            )
        )
    }

    @Test("TC-MAC-PAG-07: Outbox/non-syncable blocks catch-up")
    func outboxOrNonsyncableBlocksCatchUp() {
        #expect(
            !MacPaginationRuleEngine.shouldAttemptCatchUp(
                hasMorePages: false,
                isUnifiedMode: false,
                isSearchActive: false,
                hasSelectedFolder: true,
                isOutboxSelected: true,
                folderType: nil,
                folderImapPath: ""
            )
        )

        #expect(
            !MacPaginationRuleEngine.shouldAttemptCatchUp(
                hasMorePages: false,
                isUnifiedMode: false,
                isSearchActive: false,
                hasSelectedFolder: true,
                isOutboxSelected: false,
                folderType: "virtual",
                folderImapPath: "VIRTUAL"
            )
        )
    }

    @Test("TC-MAC-PAG-09: sentinel hidden when boundary reached and no local pages")
    func sentinelHiddenAtBoundary() {
        #expect(
            !MacPaginationRuleEngine.shouldShowSentinel(
                hasMorePages: false,
                isCatchUpEligibleContext: true,
                reachedServerHistoryBoundary: true
            )
        )
    }
}
#endif
