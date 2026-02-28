import SwiftUI

/// Semantic color tokens for the VaultMail theming engine.
///
/// Every color in the app is expressed through one of these tokens.
/// Themes define concrete values; views read tokens via `ThemeProvider.colors`.
///
/// Spec ref: FR-CO-01, FR-CO-02, FR-CO-03
public struct ThemeColors: Sendable {

    // MARK: - Backgrounds

    /// Root screen background.
    public let background: Color
    /// Cards, sheets, list rows.
    public let surface: Color
    /// Modals, popovers, search bar fill.
    public let surfaceElevated: Color
    /// Selected / highlighted rows — subtle neutral.
    public let surfaceSelected: Color
    /// Hover highlight on macOS rows.
    public let surfaceHovered: Color

    // MARK: - Text

    /// Headings, sender names — highest contrast.
    public let textPrimary: Color
    /// Body text, subjects — mid contrast (≥ 4.5:1).
    public let textSecondary: Color
    /// Timestamps, captions, snippets — still ≥ 4.5:1 (normal-text rule).
    public let textTertiary: Color
    /// Text rendered on accent-colored backgrounds (always white).
    public let textInverse: Color

    // MARK: - Accent

    /// Primary brand color — buttons, links, active states.
    public let accent: Color
    /// Subtle accent background — badges, selected rows (~12-15% opacity).
    public let accentMuted: Color
    /// Pressed / hover states — darkened (light) or lightened (dark).
    public let accentHover: Color

    // MARK: - Semantic Status

    /// Delete, spam, errors.
    public let destructive: Color
    /// Destructive background (~12-15% opacity).
    public let destructiveMuted: Color
    /// Sent, synced, online.
    public let success: Color
    /// Success background.
    public let successMuted: Color
    /// Unsaved drafts, warnings.
    public let warning: Color
    /// Warning background.
    public let warningMuted: Color

    // MARK: - UI Chrome

    /// List dividers.
    public let separator: Color
    /// Input field borders.
    public let border: Color
    /// Disabled controls.
    public let disabled: Color
    /// Loading skeleton base.
    public let shimmer: Color

    // MARK: - AI Category Colors (FR-CO-02)

    public let categoryPrimary: Color
    public let categorySocial: Color
    public let categoryPromotions: Color
    public let categoryUpdates: Color
    public let categoryForums: Color
    public let categoryUncategorized: Color

    /// Muted backgrounds for category badges.
    public let categoryPrimaryMuted: Color
    public let categorySocialMuted: Color
    public let categoryPromotionsMuted: Color
    public let categoryUpdatesMuted: Color
    public let categoryForumsMuted: Color
    public let categoryUncategorizedMuted: Color

    // MARK: - Specialized

    /// Unread indicator dot — defaults to accent.
    public let unreadDot: Color
    /// Star / flag icon color.
    public let starred: Color

    // MARK: - AI Feature Colors

    /// AI sparkles, smart reply icons — system purple.
    public let aiAccent: Color
    /// Subtle AI background / gradient border (~12-15% opacity).
    public let aiAccentMuted: Color

    // MARK: - Avatar Palette (FR-CO-03)

    /// 10 deterministic colors for contact avatars.
    public let avatarPalette: [Color]

    // MARK: - Init

    public init(
        background: Color,
        surface: Color,
        surfaceElevated: Color,
        surfaceSelected: Color,
        surfaceHovered: Color,
        textPrimary: Color,
        textSecondary: Color,
        textTertiary: Color,
        textInverse: Color,
        accent: Color,
        accentMuted: Color,
        accentHover: Color,
        destructive: Color,
        destructiveMuted: Color,
        success: Color,
        successMuted: Color,
        warning: Color,
        warningMuted: Color,
        separator: Color,
        border: Color,
        disabled: Color,
        shimmer: Color,
        categoryPrimary: Color,
        categorySocial: Color,
        categoryPromotions: Color,
        categoryUpdates: Color,
        categoryForums: Color,
        categoryUncategorized: Color,
        categoryPrimaryMuted: Color,
        categorySocialMuted: Color,
        categoryPromotionsMuted: Color,
        categoryUpdatesMuted: Color,
        categoryForumsMuted: Color,
        categoryUncategorizedMuted: Color,
        unreadDot: Color,
        starred: Color,
        aiAccent: Color,
        aiAccentMuted: Color,
        avatarPalette: [Color]
    ) {
        self.background = background
        self.surface = surface
        self.surfaceElevated = surfaceElevated
        self.surfaceSelected = surfaceSelected
        self.surfaceHovered = surfaceHovered
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.textInverse = textInverse
        self.accent = accent
        self.accentMuted = accentMuted
        self.accentHover = accentHover
        self.destructive = destructive
        self.destructiveMuted = destructiveMuted
        self.success = success
        self.successMuted = successMuted
        self.warning = warning
        self.warningMuted = warningMuted
        self.separator = separator
        self.border = border
        self.disabled = disabled
        self.shimmer = shimmer
        self.categoryPrimary = categoryPrimary
        self.categorySocial = categorySocial
        self.categoryPromotions = categoryPromotions
        self.categoryUpdates = categoryUpdates
        self.categoryForums = categoryForums
        self.categoryUncategorized = categoryUncategorized
        self.categoryPrimaryMuted = categoryPrimaryMuted
        self.categorySocialMuted = categorySocialMuted
        self.categoryPromotionsMuted = categoryPromotionsMuted
        self.categoryUpdatesMuted = categoryUpdatesMuted
        self.categoryForumsMuted = categoryForumsMuted
        self.categoryUncategorizedMuted = categoryUncategorizedMuted
        self.unreadDot = unreadDot
        self.starred = starred
        self.aiAccent = aiAccent
        self.aiAccentMuted = aiAccentMuted
        self.avatarPalette = avatarPalette
    }
}
