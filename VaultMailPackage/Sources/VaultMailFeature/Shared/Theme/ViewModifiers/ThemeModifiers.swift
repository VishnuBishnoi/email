import SwiftUI

// MARK: - Themed View Modifiers

/// Convenience `View` extensions that apply semantic design tokens from
/// the current `ThemeProvider`. Each modifier reads the theme from the
/// environment, so views automatically re-render when the theme changes.
///
/// Spec ref: FR-CS-01
extension View {

    // MARK: - Card

    /// Card style: `surface` background, `medium` corner radius, `shadowMedium`.
    ///
    /// Usage: `.vmCard(theme)` on any container that should look like a card.
    public func vmCard(_ theme: ThemeProvider) -> some View {
        self
            .background(theme.colors.surface, in: theme.shapes.mediumRect)
            .vmShadow(theme.shapes.shadowMedium)
    }

    // MARK: - Chip / Pill

    /// Chip style: capsule with `accentMuted` background, `labelMedium` font, accent text.
    ///
    /// Usage: `.vmChip(theme)` on a `Text` or small `HStack`.
    public func vmChip(_ theme: ThemeProvider) -> some View {
        self
            .font(theme.typography.labelMedium)
            .foregroundStyle(theme.colors.accent)
            .padding(.horizontal, theme.spacing.chipHorizontal)
            .padding(.vertical, theme.spacing.chipVertical)
            .background(theme.colors.accentMuted, in: Capsule())
    }

    // MARK: - Primary Button

    /// Primary button: accent background, inverse text, large corner radius.
    public func vmPrimaryButton(_ theme: ThemeProvider) -> some View {
        self
            .font(theme.typography.labelLarge)
            .foregroundStyle(theme.colors.textInverse)
            .padding(.horizontal, theme.spacing.xl)
            .padding(.vertical, theme.spacing.md)
            .background(theme.colors.accent, in: theme.shapes.largeRect)
    }

    // MARK: - Secondary Button

    /// Secondary button: border + accent text, large corner radius.
    public func vmSecondaryButton(_ theme: ThemeProvider) -> some View {
        self
            .font(theme.typography.labelLarge)
            .foregroundStyle(theme.colors.accent)
            .padding(.horizontal, theme.spacing.xl)
            .padding(.vertical, theme.spacing.md)
            .overlay(theme.shapes.largeRect.stroke(theme.colors.border, lineWidth: 1))
    }

    // MARK: - Search Bar

    /// Search bar: surfaceElevated background, small corner radius, border.
    public func vmSearchBar(_ theme: ThemeProvider) -> some View {
        self
            .padding(.horizontal, theme.spacing.md)
            .frame(height: theme.spacing.searchBarHeight)
            .background(theme.colors.surfaceElevated, in: theme.shapes.smallRect)
            .overlay(theme.shapes.smallRect.stroke(theme.colors.border, lineWidth: 0.5))
    }

    // MARK: - Section Header

    /// Section header: `titleSmall` font, `textSecondary` color.
    public func vmSectionHeader(_ theme: ThemeProvider) -> some View {
        self
            .font(theme.typography.titleSmall)
            .foregroundStyle(theme.colors.textSecondary)
    }

    // MARK: - List Row

    /// Comfortable list row padding from theme spacing tokens.
    public func vmListRow(_ theme: ThemeProvider) -> some View {
        self
            .padding(.vertical, theme.spacing.listRowVertical)
            .padding(.horizontal, theme.spacing.listRowHorizontal)
    }

    // MARK: - Toast

    /// Toast overlay: material background, medium corner radius, shadow.
    public func vmToast(_ theme: ThemeProvider) -> some View {
        self
            .padding(.horizontal, theme.spacing.lg)
            .padding(.vertical, theme.spacing.md)
            .background(.thinMaterial, in: theme.shapes.mediumRect)
            .padding(.horizontal, theme.spacing.lg)
            .padding(.bottom, theme.spacing.lg)
            .frame(maxWidth: .infinity)
    }
}
