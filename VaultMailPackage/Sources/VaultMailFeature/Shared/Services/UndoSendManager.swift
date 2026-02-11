import Foundation

/// Observable service managing the undo-send countdown timer.
///
/// Created at ContentView level and injected via `.environment()`.
/// ThreadListView overlays `UndoSendToastView` when countdown is active.
///
/// Timer behavior per FR-COMP-02:
/// - Pauses when app enters background, resumes on foreground
/// - If app terminated during countdown, email stays as queued in SwiftData
///   (will be reverted to draft on next launch — handled by ContentView)
/// - Calls `onExpired` when countdown reaches zero to trigger actual send
///
/// Spec ref: Email Composer FR-COMP-02
@Observable
@MainActor
public final class UndoSendManager {

    /// The email ID currently in undo-send countdown.
    public var activeEmailId: String? = nil

    /// Seconds remaining in the countdown.
    public var remainingSeconds: Int = 0

    /// Whether a countdown is currently active.
    public var isCountdownActive: Bool {
        activeEmailId != nil && remainingSeconds > 0
    }

    /// Whether the countdown is paused (app backgrounded).
    private var isPaused = false

    /// The countdown task.
    private var countdownTask: Task<Void, Never>?

    /// Callback when the timer expires (trigger actual send).
    private var onExpired: ((String) async -> Void)?

    public init() {}

    /// Start the undo-send countdown for an email.
    ///
    /// - Parameters:
    ///   - emailId: The queued email's ID.
    ///   - delaySeconds: The countdown duration (from settings).
    ///   - onExpired: Called when countdown reaches zero (execute send).
    public func startCountdown(
        emailId: String,
        delaySeconds: Int,
        onExpired: @escaping (String) async -> Void
    ) {
        cancelCountdown()

        guard delaySeconds > 0 else {
            // Undo disabled (0s) — send immediately
            Task { await onExpired(emailId) }
            return
        }

        activeEmailId = emailId
        remainingSeconds = delaySeconds
        self.onExpired = onExpired

        countdownTask = Task { [weak self] in
            while let self, self.remainingSeconds > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                guard !self.isPaused else { continue }
                self.remainingSeconds -= 1
            }

            // Timer expired — trigger send
            guard !Task.isCancelled, let self, let emailId = self.activeEmailId else { return }
            let callback = self.onExpired
            self.activeEmailId = nil
            self.remainingSeconds = 0
            self.onExpired = nil
            await callback?(emailId)
        }
    }

    /// Undo the send: cancel countdown and return the email ID for revert.
    /// - Returns: The email ID that was being counted down, or nil.
    @discardableResult
    public func undoSend() -> String? {
        let emailId = activeEmailId
        cancelCountdown()
        return emailId
    }

    /// Pause the countdown (app entered background).
    public func pause() {
        isPaused = true
    }

    /// Resume the countdown (app returned to foreground).
    public func resume() {
        isPaused = false
    }

    /// Cancel any active countdown.
    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        activeEmailId = nil
        remainingSeconds = 0
        isPaused = false
        onExpired = nil
    }
}
