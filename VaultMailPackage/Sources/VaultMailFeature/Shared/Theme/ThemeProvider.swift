import SwiftUI

/// Observable theme provider injected via `@Environment(ThemeProvider.self)`.
///
/// **Pure in-memory** — does NOT read from or write to UserDefaults.
/// All persistence is owned exclusively by `SettingsStore.selectedThemeId`.
///
/// Coordination flow:
/// 1. User taps theme → view writes `settings.selectedThemeId`
/// 2. View calls `themeProvider.apply(themeId)` to update in-memory
/// 3. On launch, app root passes `settings.selectedThemeId` to init
///
/// Spec ref: FR-TH-02
@Observable
@MainActor
public final class ThemeProvider {

    /// The currently active theme (in-memory only).
    public private(set) var currentTheme: any VaultMailTheme

    /// The active color scheme, updated from SwiftUI environment.
    public var colorScheme: ColorScheme = .light

    // MARK: - Convenience Accessors

    /// Color tokens resolved for the current color scheme.
    public var colors: ThemeColors { currentTheme.colors(for: colorScheme) }
    /// Typography tokens.
    public var typography: ThemeTypography { currentTheme.typography }
    /// Spacing tokens.
    public var spacing: ThemeSpacing { currentTheme.spacing }
    /// Shape tokens resolved for the current color scheme (shadows suppressed in dark).
    public var shapes: ThemeShapes { currentTheme.shapes(for: colorScheme) }

    // MARK: - Init

    /// Creates a provider with the given theme ID.
    /// Falls back to the default theme if the ID is unknown.
    public init(themeId: String = "default") {
        self.currentTheme = ThemeRegistry.theme(for: themeId)
    }

    // MARK: - Theme Switching

    /// Swaps the current theme in memory. Does NOT persist — caller is
    /// responsible for writing `SettingsStore.selectedThemeId`.
    public func apply(_ themeId: String) {
        self.currentTheme = ThemeRegistry.theme(for: themeId)
    }
}
