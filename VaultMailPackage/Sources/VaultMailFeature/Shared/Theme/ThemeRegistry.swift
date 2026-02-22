import Foundation

/// Catalog of all built-in themes.
///
/// Spec ref: FR-TH-03
public enum ThemeRegistry {

    /// All built-in themes in display order.
    public static let allThemes: [any VaultMailTheme] = [
        DefaultTheme(),
        MidnightTheme(),
        ForestTheme(),
        SunsetTheme(),
        LavenderTheme(),
        RoseTheme(),
    ]

    /// Resolves a theme by ID. Falls back to `DefaultTheme` if unknown.
    public static func theme(for id: String) -> any VaultMailTheme {
        allThemes.first { $0.id == id } ?? DefaultTheme()
    }
}
