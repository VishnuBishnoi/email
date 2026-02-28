#if os(macOS)
import Testing
@testable import VaultMailFeature

@Suite("MacThreadListContentView Footer Mode")
struct MacThreadListContentViewTests {
    @Test("TC-MAC-PAG-09: sentinel mode when no pagination error and sentinel condition true")
    func sentinelMode() {
        let mode = MacThreadListPaginationFooterMode.resolve(
            hasMorePages: true,
            shouldShowServerCatchUpSentinel: true,
            paginationError: false
        )
        #expect(mode == .localSentinel)
    }

    @Test("catch-up sentinel mode when local pages are exhausted and catch-up is eligible")
    func catchUpSentinelMode() {
        let mode = MacThreadListPaginationFooterMode.resolve(
            hasMorePages: false,
            shouldShowServerCatchUpSentinel: true,
            paginationError: false
        )
        #expect(mode == .catchUpSentinel)
    }

    @Test("TC-MAC-PAG-10: retry mode has priority over sentinel when pagination error is present")
    func retryModePriority() {
        let mode = MacThreadListPaginationFooterMode.resolve(
            hasMorePages: true,
            shouldShowServerCatchUpSentinel: true,
            paginationError: true
        )
        #expect(mode == .retry)
    }

    @Test("footer mode none when no sentinel and no error")
    func noFooterMode() {
        let mode = MacThreadListPaginationFooterMode.resolve(
            hasMorePages: false,
            shouldShowServerCatchUpSentinel: false,
            paginationError: false
        )
        #expect(mode == .none)
    }
}
#endif
