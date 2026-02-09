import Foundation
import Testing
@testable import PrivateMailFeature

@Suite("UndoSendManager")
@MainActor
struct UndoSendManagerTests {

    // MARK: - Helpers

    private static func makeSUT() -> UndoSendManager {
        UndoSendManager()
    }

    // MARK: - Initial State

    @Test("Initial state is inactive")
    func initialState() {
        let manager = Self.makeSUT()

        #expect(manager.activeEmailId == nil)
        #expect(manager.remainingSeconds == 0)
        #expect(manager.isCountdownActive == false)
    }

    // MARK: - Start Countdown

    @Test("Starting countdown sets active state")
    func startCountdownSetsState() async {
        let manager = Self.makeSUT()

        manager.startCountdown(emailId: "email-1", delaySeconds: 10) { _ in }

        #expect(manager.activeEmailId == "email-1")
        #expect(manager.remainingSeconds == 10)
        #expect(manager.isCountdownActive == true)
    }

    @Test("Starting countdown with 0 delay sends immediately")
    func zeroDelayImmediate() async throws {
        let manager = Self.makeSUT()
        var sentEmailId: String?

        manager.startCountdown(emailId: "email-1", delaySeconds: 0) { emailId in
            sentEmailId = emailId
        }

        // Give the Task a moment to execute
        try await Task.sleep(for: .milliseconds(100))

        #expect(sentEmailId == "email-1")
        #expect(manager.isCountdownActive == false)
    }

    @Test("Countdown decrements remaining seconds")
    func countdownDecrements() async throws {
        let manager = Self.makeSUT()

        manager.startCountdown(emailId: "email-1", delaySeconds: 5) { _ in }

        #expect(manager.remainingSeconds == 5)

        // Wait for 2 seconds to reliably catch at least one timer tick
        try await Task.sleep(for: .milliseconds(2500))

        #expect(manager.remainingSeconds < 5)
        #expect(manager.isCountdownActive == true)
    }

    // MARK: - Undo

    @Test("Undo cancels countdown and returns email ID")
    func undoCancels() {
        let manager = Self.makeSUT()

        manager.startCountdown(emailId: "email-1", delaySeconds: 10) { _ in }

        let emailId = manager.undoSend()

        #expect(emailId == "email-1")
        #expect(manager.activeEmailId == nil)
        #expect(manager.remainingSeconds == 0)
        #expect(manager.isCountdownActive == false)
    }

    @Test("Undo with no active countdown returns nil")
    func undoWhenInactive() {
        let manager = Self.makeSUT()

        let emailId = manager.undoSend()

        #expect(emailId == nil)
    }

    // MARK: - Pause / Resume

    @Test("Pause stops decrementing, resume continues")
    func pauseAndResume() async throws {
        let manager = Self.makeSUT()

        manager.startCountdown(emailId: "email-1", delaySeconds: 10) { _ in }

        // Wait for one tick
        try await Task.sleep(for: .milliseconds(1200))
        let afterOneTick = manager.remainingSeconds

        // Pause
        manager.pause()
        try await Task.sleep(for: .milliseconds(1500))
        let afterPause = manager.remainingSeconds

        // Should not have decremented further while paused
        #expect(afterPause == afterOneTick)

        // Resume
        manager.resume()
        try await Task.sleep(for: .milliseconds(1200))
        let afterResume = manager.remainingSeconds

        // Should have decremented after resume
        #expect(afterResume < afterPause)
    }

    // MARK: - Restart

    @Test("Starting new countdown cancels previous one")
    func startCancelsPrevious() {
        let manager = Self.makeSUT()

        manager.startCountdown(emailId: "email-1", delaySeconds: 10) { _ in }
        manager.startCountdown(emailId: "email-2", delaySeconds: 5) { _ in }

        #expect(manager.activeEmailId == "email-2")
        #expect(manager.remainingSeconds == 5)
    }

    // MARK: - isCountdownActive

    @Test("isCountdownActive is false when emailId is nil")
    func isCountdownActiveNoEmail() {
        let manager = Self.makeSUT()
        #expect(manager.isCountdownActive == false)
    }

    @Test("isCountdownActive is false when remainingSeconds is 0")
    func isCountdownActiveZeroSeconds() {
        let manager = Self.makeSUT()
        // This tests the computed property directly
        #expect(manager.isCountdownActive == false)
    }

    // MARK: - Expiry Callback

    @Test("Callback fires when countdown expires")
    func callbackOnExpiry() async throws {
        let manager = Self.makeSUT()
        var expiredEmailId: String?

        manager.startCountdown(emailId: "email-1", delaySeconds: 2) { emailId in
            expiredEmailId = emailId
        }

        // Wait for countdown to complete (2 seconds + buffer)
        try await Task.sleep(for: .milliseconds(3000))

        #expect(expiredEmailId == "email-1")
        #expect(manager.isCountdownActive == false)
        #expect(manager.activeEmailId == nil)
    }
}
