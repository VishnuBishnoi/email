import Foundation

/// AI-powered email categorization values.
///
/// Spec ref: Foundation spec Section 5.2
public enum AICategory: String, Codable, CaseIterable, Sendable {
    /// Direct, personal communication
    case primary
    /// Social network notifications and messages
    case social
    /// Marketing, deals, offers
    case promotions
    /// Bills, receipts, statements, confirmations
    case updates
    /// Mailing lists, group discussions
    case forums
    /// Not yet processed by AI
    case uncategorized
}
