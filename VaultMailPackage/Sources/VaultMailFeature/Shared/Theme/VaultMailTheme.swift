import SwiftUI

/// Contract for all VaultMail themes.
///
/// Conforms to `Identifiable` for use in `ForEach`.
/// Use `ForEach(ThemeRegistry.allThemes, id: \.id)` for existential iteration.
///
/// Spec ref: FR-TH-01
public protocol VaultMailTheme: Sendable, Identifiable where ID == String {
    /// Unique theme identifier (e.g., "default", "midnight").
    var id: String { get }
    /// Human-readable name for the Settings picker (e.g., "VaultMail").
    var displayName: String { get }
    /// Accent color shown in the theme picker circles.
    var previewColor: Color { get }

    /// Returns color tokens resolved for the given color scheme.
    func colors(for scheme: ColorScheme) -> ThemeColors
    /// Typography tokens (shared across light/dark).
    var typography: ThemeTypography { get }
    /// Spacing tokens (shared across light/dark).
    var spacing: ThemeSpacing { get }
    /// Shape tokens resolved for the given color scheme (shadows suppressed in dark).
    func shapes(for scheme: ColorScheme) -> ThemeShapes
}
