import Foundation

/// Undo send delay options in seconds.
///
/// Spec ref: Settings & Onboarding spec FR-SET-01 (Composition section)
/// Cross-ref: Email Composer FR-COMP-02
public enum UndoSendDelay: Int, Codable, CaseIterable, Sendable {
    case disabled = 0
    case fiveSeconds = 5
    case tenSeconds = 10
    case fifteenSeconds = 15
    case thirtySeconds = 30

    /// Human-readable label for picker UI.
    public var displayLabel: String {
        switch self {
        case .disabled: "Off"
        case .fiveSeconds: "5 seconds"
        case .tenSeconds: "10 seconds"
        case .fifteenSeconds: "15 seconds"
        case .thirtySeconds: "30 seconds"
        }
    }
}
