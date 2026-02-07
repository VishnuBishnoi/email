import Foundation

/// Email send pipeline state.
///
/// State machine transitions are defined in the Email Composer spec (FR-COMP-02)
/// and Email Sync spec (FR-SYNC-07).
///
/// Spec ref: Foundation spec Section 5.5
public enum SendState: String, Codable, CaseIterable, Sendable {
    /// Normal received email, not in send pipeline
    case none
    /// Composed and queued for sending (includes undo-send delay period)
    case queued
    /// SMTP transmission in progress
    case sending
    /// Send failed after retries; user action required
    case failed
    /// Successfully delivered via SMTP
    case sent
}
