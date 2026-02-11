import Foundation
import Testing
@testable import VaultMailFeature

/// Validates that all error enums have LocalizedError conformance with
/// non-nil errorDescription for every case.
@Suite("Error Enums")
struct ErrorTests {

    // MARK: - AccountError (6 cases)

    @Test("AccountError has 6 cases with non-nil descriptions")
    func accountErrorDescriptions() {
        let cases: [AccountError] = [
            .notFound("id-1"),
            .duplicateAccount("user@gmail.com"),
            .keychainFailure(.itemNotFound),
            .oauthFailure(.authenticationCancelled),
            .persistenceFailed("disk full"),
            .imapValidationFailed("connection refused")
        ]
        #expect(cases.count == 6)
        for error in cases {
            #expect(error.errorDescription != nil, "AccountError.\(error) has nil errorDescription")
        }
    }

    // MARK: - IMAPError (10 cases)

    @Test("IMAPError has 10 cases with non-nil descriptions")
    func imapErrorDescriptions() {
        let cases: [IMAPError] = [
            .connectionFailed("timeout"),
            .authenticationFailed("bad token"),
            .commandFailed("NO"),
            .invalidResponse("garbage"),
            .folderNotFound("INBOX"),
            .messageNotFound("123"),
            .parsingFailed("bad MIME"),
            .operationCancelled,
            .timeout,
            .maxRetriesExhausted
        ]
        #expect(cases.count == 10)
        for error in cases {
            #expect(error.errorDescription != nil, "IMAPError.\(error) has nil errorDescription")
        }
    }

    // MARK: - SMTPError (8 cases)

    @Test("SMTPError has 8 cases with non-nil descriptions")
    func smtpErrorDescriptions() {
        let cases: [SMTPError] = [
            .connectionFailed("refused"),
            .authenticationFailed("bad credentials"),
            .commandFailed("550"),
            .invalidResponse("garbage"),
            .operationCancelled,
            .timeout,
            .maxRetriesExhausted,
            .encodingFailed("invalid UTF-8")
        ]
        #expect(cases.count == 8)
        for error in cases {
            #expect(error.errorDescription != nil, "SMTPError.\(error) has nil errorDescription")
        }
    }

    // MARK: - OAuthError (8 cases)

    @Test("OAuthError has 8 cases with non-nil descriptions")
    func oauthErrorDescriptions() {
        let cases: [OAuthError] = [
            .authenticationCancelled,
            .invalidAuthorizationCode,
            .tokenExchangeFailed("server error"),
            .tokenRefreshFailed("expired"),
            .invalidResponse,
            .maxRetriesExceeded,
            .networkError("no internet"),
            .noRefreshToken
        ]
        #expect(cases.count == 8)
        for error in cases {
            #expect(error.errorDescription != nil, "OAuthError.\(error) has nil errorDescription")
        }
    }

    // MARK: - KeychainError (6 cases)

    @Test("KeychainError has 6 cases with non-nil descriptions")
    func keychainErrorDescriptions() {
        let cases: [KeychainError] = [
            .itemNotFound,
            .unableToStore(-25299),
            .unableToRetrieve(-25300),
            .unableToDelete(-25301),
            .encodingFailed,
            .decodingFailed
        ]
        #expect(cases.count == 6)
        for error in cases {
            #expect(error.errorDescription != nil, "KeychainError.\(error) has nil errorDescription")
        }
    }

    // MARK: - SyncError (7 cases)

    @Test("SyncError has 7 cases with non-nil descriptions")
    func syncErrorDescriptions() {
        let cases: [SyncError] = [
            .accountNotFound("acc-1"),
            .accountInactive("acc-2"),
            .folderNotFound("INBOX"),
            .tokenRefreshFailed("expired"),
            .connectionFailed("timeout"),
            .syncFailed("unknown"),
            .timeout
        ]
        #expect(cases.count == 7)
        for error in cases {
            #expect(error.errorDescription != nil, "SyncError.\(error) has nil errorDescription")
        }
    }

    // MARK: - ComposerError (6 cases — FIXED)

    @Test("ComposerError has 6 cases with non-nil descriptions")
    func composerErrorDescriptions() {
        let cases: [ComposerError] = [
            .saveDraftFailed("disk full"),
            .sendFailed("SMTP error"),
            .deleteDraftFailed("not found"),
            .invalidRecipient("bad@"),
            .attachmentTooLarge(totalMB: 30),
            .contactQueryFailed("access denied")
        ]
        #expect(cases.count == 6)
        for error in cases {
            #expect(error.errorDescription != nil, "ComposerError.\(error) has nil errorDescription")
        }
    }

    @Test("ComposerError descriptions contain context")
    func composerErrorDescriptionContent() {
        #expect(ComposerError.saveDraftFailed("disk full").errorDescription?.contains("disk full") == true)
        #expect(ComposerError.sendFailed("timeout").errorDescription?.contains("timeout") == true)
        #expect(ComposerError.invalidRecipient("bad@addr").errorDescription?.contains("bad@addr") == true)
        #expect(ComposerError.attachmentTooLarge(totalMB: 30).errorDescription?.contains("30") == true)
    }

    // MARK: - EmailDetailError (5 cases — FIXED)

    @Test("EmailDetailError has 5 cases with non-nil descriptions")
    func emailDetailErrorDescriptions() {
        let cases: [EmailDetailError] = [
            .threadNotFound(id: "t-1"),
            .loadFailed("corrupt data"),
            .markReadFailed("network error"),
            .actionFailed("server rejected"),
            .downloadFailed("timeout")
        ]
        #expect(cases.count == 5)
        for error in cases {
            #expect(error.errorDescription != nil, "EmailDetailError.\(error) has nil errorDescription")
        }
    }

    @Test("EmailDetailError descriptions contain context")
    func emailDetailErrorDescriptionContent() {
        #expect(EmailDetailError.threadNotFound(id: "t-42").errorDescription?.contains("t-42") == true)
        #expect(EmailDetailError.downloadFailed("timeout").errorDescription?.contains("timeout") == true)
    }

    // MARK: - ThreadListError (4 cases — FIXED)

    @Test("ThreadListError has 4 cases with non-nil descriptions")
    func threadListErrorDescriptions() {
        let cases: [ThreadListError] = [
            .fetchFailed("network error"),
            .actionFailed("permission denied"),
            .threadNotFound(id: "t-1"),
            .folderNotFound(id: "f-1")
        ]
        #expect(cases.count == 4)
        for error in cases {
            #expect(error.errorDescription != nil, "ThreadListError.\(error) has nil errorDescription")
        }
    }

    @Test("ThreadListError descriptions contain context")
    func threadListErrorDescriptionContent() {
        #expect(ThreadListError.fetchFailed("timeout").errorDescription?.contains("timeout") == true)
        #expect(ThreadListError.threadNotFound(id: "t-99").errorDescription?.contains("t-99") == true)
        #expect(ThreadListError.folderNotFound(id: "f-7").errorDescription?.contains("f-7") == true)
    }

    // MARK: - FTS5Error

    @Test("FTS5Error cases have meaningful descriptions via localizedDescription")
    func fts5ErrorDescriptions() {
        let cases: [FTS5Error] = [
            .databaseNotOpen,
            .sqliteError(code: 1, message: "test error"),
            .corruptDatabase,
            .invalidQuery
        ]
        // FTS5Error doesn't have LocalizedError, but verify it exists and conforms to Error
        for error in cases {
            #expect(!error.localizedDescription.isEmpty)
        }
    }

    // MARK: - Equatable Conformance

    @Test("ComposerError Equatable works correctly")
    func composerErrorEquatable() {
        #expect(ComposerError.saveDraftFailed("a") == ComposerError.saveDraftFailed("a"))
        #expect(ComposerError.saveDraftFailed("a") != ComposerError.saveDraftFailed("b"))
        #expect(ComposerError.sendFailed("x") != ComposerError.saveDraftFailed("x"))
    }

    @Test("EmailDetailError Equatable works correctly")
    func emailDetailErrorEquatable() {
        #expect(EmailDetailError.loadFailed("a") == EmailDetailError.loadFailed("a"))
        #expect(EmailDetailError.loadFailed("a") != EmailDetailError.loadFailed("b"))
        #expect(EmailDetailError.downloadFailed("x") != EmailDetailError.loadFailed("x"))
    }

    @Test("ThreadListError Equatable works correctly")
    func threadListErrorEquatable() {
        #expect(ThreadListError.fetchFailed("a") == ThreadListError.fetchFailed("a"))
        #expect(ThreadListError.fetchFailed("a") != ThreadListError.actionFailed("a"))
    }
}
