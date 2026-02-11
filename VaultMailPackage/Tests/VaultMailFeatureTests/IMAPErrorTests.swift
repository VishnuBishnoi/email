import Foundation
import Testing
@testable import VaultMailFeature

/// Tests for IMAP error types.
///
/// Validates that IMAPError cases have proper descriptions
/// and conform to required protocols.
///
/// Spec ref: Email Sync spec FR-SYNC-09
@Suite("IMAP Error Types")
struct IMAPErrorTests {

    @Test("IMAPError conforms to Equatable")
    func equatable() {
        #expect(IMAPError.timeout == IMAPError.timeout)
        #expect(IMAPError.operationCancelled == IMAPError.operationCancelled)
        #expect(IMAPError.maxRetriesExhausted == IMAPError.maxRetriesExhausted)
        #expect(IMAPError.connectionFailed("a") == IMAPError.connectionFailed("a"))
        #expect(IMAPError.connectionFailed("a") != IMAPError.connectionFailed("b"))
        #expect(IMAPError.timeout != IMAPError.operationCancelled)
    }

    @Test("IMAPError conforms to Sendable")
    func sendable() {
        // This test verifies at compile time that IMAPError is Sendable
        let error: any Sendable = IMAPError.timeout
        #expect(error is IMAPError)
    }

    @Test("connectionFailed has descriptive message")
    func connectionFailedDescription() {
        let error = IMAPError.connectionFailed("TLS handshake failed")
        #expect(error.errorDescription?.contains("Connection Failed") == true)
        #expect(error.errorDescription?.contains("TLS handshake failed") == true)
    }

    @Test("authenticationFailed has descriptive message")
    func authenticationFailedDescription() {
        let error = IMAPError.authenticationFailed("XOAUTH2 rejected")
        #expect(error.errorDescription?.contains("Authentication Failed") == true)
        #expect(error.errorDescription?.contains("XOAUTH2 rejected") == true)
    }

    @Test("timeout has descriptive message")
    func timeoutDescription() {
        let error = IMAPError.timeout
        #expect(error.errorDescription?.contains("Timed Out") == true)
    }

    @Test("folderNotFound includes folder name")
    func folderNotFoundDescription() {
        let error = IMAPError.folderNotFound("INBOX")
        #expect(error.errorDescription?.contains("INBOX") == true)
    }

    @Test("messageNotFound includes UID")
    func messageNotFoundDescription() {
        let error = IMAPError.messageNotFound("12345")
        #expect(error.errorDescription?.contains("12345") == true)
    }

    @Test("maxRetriesExhausted has descriptive message")
    func maxRetriesExhaustedDescription() {
        let error = IMAPError.maxRetriesExhausted
        #expect(error.errorDescription?.contains("Retries") == true)
    }

    @Test("All error cases produce non-nil descriptions")
    func allCasesHaveDescriptions() {
        let errors: [IMAPError] = [
            .connectionFailed("test"),
            .authenticationFailed("test"),
            .commandFailed("test"),
            .invalidResponse("test"),
            .folderNotFound("test"),
            .messageNotFound("test"),
            .parsingFailed("test"),
            .operationCancelled,
            .timeout,
            .maxRetriesExhausted,
        ]

        for error in errors {
            #expect(error.errorDescription != nil, "Missing description for: \(error)")
            #expect(!error.errorDescription!.isEmpty, "Empty description for: \(error)")
        }
    }
}
