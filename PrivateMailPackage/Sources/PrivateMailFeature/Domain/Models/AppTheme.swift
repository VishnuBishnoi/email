import Foundation

/// App appearance theme.
///
/// Spec ref: Settings & Onboarding spec Section 5 (Settings Enums)
public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    /// Human-readable label for picker UI.
    public var displayLabel: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
