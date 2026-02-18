import Foundation
import Testing
@testable import VaultMailFeature

@Suite("ConnectionTestUseCase Tests")
@MainActor
struct ConnectionTestUseCaseTests {

    // MARK: - Helpers

    private let mockIMAPClient = MockIMAPClient()
    private let mockSMTPClient = MockSMTPClient()

    private func makeSUT() -> ConnectionTestUseCase {
        let imap = mockIMAPClient
        let smtp = mockSMTPClient
        return ConnectionTestUseCase(
            imapClientFactory: { imap },
            smtpClientFactory: { smtp }
        )
    }

    /// Collects all results from the stream in a detached task to avoid
    /// main-actor deadlock (the producer task is also @MainActor).
    private func collectResults(
        from stream: AsyncStream<ConnectionTestResult>
    ) async -> [ConnectionTestResult] {
        let task = Task.detached {
            var results: [ConnectionTestResult] = []
            for await result in stream {
                results.append(result)
            }
            return results
        }
        return await task.value
    }

    // MARK: - Happy Path

    @Test("All steps succeed when both IMAP and SMTP connect successfully")
    func allStepsSucceed() async throws {
        let sut = makeSUT()

        let stream = sut.testConnection(
            imapHost: "imap.example.com", imapPort: 993, imapSecurity: .tls,
            smtpHost: "smtp.example.com", smtpPort: 587, smtpSecurity: .starttls,
            email: "test@example.com", password: "secret"
        )

        let results = await collectResults(from: stream)

        // Should have multiple status updates
        #expect(!results.isEmpty)

        // Final result should have all steps passed
        let final = try #require(results.last)
        #expect(final.allPassed == true)
        #expect(final.hasFailed == false)
        #expect(final.imapConnect == .success)
        #expect(final.imapAuth == .success)
        #expect(final.smtpConnect == .success)
        #expect(final.smtpAuth == .success)
    }

    // MARK: - IMAP Failure

    @Test("IMAP connection failure skips remaining steps")
    func imapConnectionFails() async throws {
        mockIMAPClient.connectError = .connectionFailed("Connection refused")
        let sut = makeSUT()

        let stream = sut.testConnection(
            imapHost: "bad.example.com", imapPort: 993, imapSecurity: .tls,
            smtpHost: "smtp.example.com", smtpPort: 587, smtpSecurity: .starttls,
            email: "test@example.com", password: "secret"
        )

        let results = await collectResults(from: stream)
        let final = try #require(results.last)

        #expect(final.allPassed == false)
        #expect(final.hasFailed == true)

        // IMAP connect should have failed
        if case .failure = final.imapConnect {
            // expected
        } else {
            Issue.record("Expected IMAP connect failure")
        }

        // SMTP steps should be skipped
        if case .failure(let msg) = final.smtpConnect {
            #expect(msg == "Skipped")
        }
    }

    // MARK: - SMTP Failure

    @Test("SMTP failure doesn't affect IMAP results")
    func smtpConnectionFails() async throws {
        await mockSMTPClient.setThrowOnConnect(true)
        let sut = makeSUT()

        let stream = sut.testConnection(
            imapHost: "imap.example.com", imapPort: 993, imapSecurity: .tls,
            smtpHost: "bad-smtp.example.com", smtpPort: 587, smtpSecurity: .starttls,
            email: "test@example.com", password: "secret"
        )

        let results = await collectResults(from: stream)
        let final = try #require(results.last)

        // IMAP should still be successful
        #expect(final.imapConnect == .success)
        #expect(final.imapAuth == .success)

        // SMTP should have failed
        #expect(final.allPassed == false)
        if case .failure = final.smtpConnect {
            // expected
        } else {
            Issue.record("Expected SMTP connect failure")
        }
    }

    // MARK: - ConnectionTestResult

    @Test("ConnectionTestResult.allPassed returns true only when all succeed")
    func allPassedProperty() {
        var result = ConnectionTestResult()
        #expect(result.allPassed == false)

        result.imapConnect = .success
        result.imapAuth = .success
        result.smtpConnect = .success
        result.smtpAuth = .success
        #expect(result.allPassed == true)

        result.smtpAuth = .failure("auth failed")
        #expect(result.allPassed == false)
    }

    @Test("ConnectionTestResult.hasFailed returns true when any step fails")
    func hasFailedProperty() {
        var result = ConnectionTestResult()
        #expect(result.hasFailed == false)

        result.imapConnect = .failure("failed")
        #expect(result.hasFailed == true)
    }

    @Test("ConnectionTestResult defaults to all pending")
    func defaultState() {
        let result = ConnectionTestResult()
        #expect(result.imapConnect == .pending)
        #expect(result.imapAuth == .pending)
        #expect(result.smtpConnect == .pending)
        #expect(result.smtpAuth == .pending)
    }

    // MARK: - Stream produces intermediate updates

    @Test("Stream emits intermediate testing states before final result")
    func intermediateUpdates() async throws {
        let sut = makeSUT()

        let stream = sut.testConnection(
            imapHost: "imap.example.com", imapPort: 993, imapSecurity: .tls,
            smtpHost: "smtp.example.com", smtpPort: 587, smtpSecurity: .starttls,
            email: "test@example.com", password: "secret"
        )

        let results = await collectResults(from: stream)

        // Should have at least 3 updates: IMAP testing, IMAP done, SMTP testing, SMTP done
        #expect(results.count >= 3)

        // First update should show IMAP testing
        if case .testing = results[0].imapConnect {
            // expected
        } else {
            Issue.record("Expected first update to show IMAP connect testing")
        }
    }
}
