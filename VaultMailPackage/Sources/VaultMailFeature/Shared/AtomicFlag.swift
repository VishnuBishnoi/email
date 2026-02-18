import Foundation

// MARK: - Thread-Safe Resume Guard

/// Atomic flag ensuring a continuation is resumed exactly once.
///
/// NWConnection callbacks and stream I/O dispatch to arbitrary queues, so
/// multiple state transitions or a timeout can race to resume the same
/// continuation. This guard prevents double-resume crashes.
///
/// Used by `IMAPSession`, `SMTPSession`, and `STARTTLSConnection`.
final class AtomicFlag: @unchecked Sendable {
    private var _value = false
    private let lock = NSLock()

    /// Tries to claim the flag. Returns `true` on the first call only.
    func trySet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !_value else { return false }
        _value = true
        return true
    }
}
