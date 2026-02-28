import Foundation
import SwiftUI
import Testing
@testable import VaultMailFeature

// MARK: - ThemeRegistry Tests

@Suite("ThemeRegistry")
struct ThemeRegistryTests {

    @Test("All 6 built-in themes are registered")
    func allThemesRegistered() {
        #expect(ThemeRegistry.allThemes.count == 6)
    }

    @Test("All theme IDs are unique")
    func uniqueIds() {
        let ids = ThemeRegistry.allThemes.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count)
    }

    @Test("All expected theme IDs are present",
          arguments: ["default", "midnight", "forest", "sunset", "lavender", "rose"])
    func expectedThemePresent(id: String) {
        let resolved = ThemeRegistry.theme(for: id)
        #expect(resolved.id == id)
    }

    @Test("Unknown theme ID falls back to default")
    func unknownIdFallsBackToDefault() {
        let theme = ThemeRegistry.theme(for: "nonexistent")
        #expect(theme.id == "default")
    }

    @Test("Empty string theme ID falls back to default")
    func emptyIdFallsBackToDefault() {
        let theme = ThemeRegistry.theme(for: "")
        #expect(theme.id == "default")
    }

    @Test("All themes have non-empty display names")
    func allDisplayNamesNonEmpty() {
        for theme in ThemeRegistry.allThemes {
            #expect(!theme.displayName.isEmpty, "Theme \(theme.id) has empty displayName")
        }
    }

    @Test("All themes have distinct display names")
    func distinctDisplayNames() {
        let names = ThemeRegistry.allThemes.map(\.displayName)
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count)
    }
}

// MARK: - ThemeProvider Tests

@Suite("ThemeProvider")
struct ThemeProviderTests {

    @Test("Default init uses default theme")
    @MainActor
    func defaultInit() {
        let provider = ThemeProvider()
        #expect(provider.currentTheme.id == "default")
    }

    @Test("Init with specific theme ID resolves correctly")
    @MainActor
    func initWithSpecificId() {
        let provider = ThemeProvider(themeId: "midnight")
        #expect(provider.currentTheme.id == "midnight")
    }

    @Test("Init with unknown theme ID falls back to default")
    @MainActor
    func initWithUnknownIdFallback() {
        let provider = ThemeProvider(themeId: "nonexistent")
        #expect(provider.currentTheme.id == "default")
    }

    @Test("apply() switches theme")
    @MainActor
    func applyTheme() {
        let provider = ThemeProvider()
        #expect(provider.currentTheme.id == "default")

        provider.apply("forest")
        #expect(provider.currentTheme.id == "forest")

        provider.apply("rose")
        #expect(provider.currentTheme.id == "rose")
    }

    @Test("apply() with unknown ID falls back to default")
    @MainActor
    func applyUnknownFallback() {
        let provider = ThemeProvider(themeId: "midnight")
        provider.apply("garbage")
        #expect(provider.currentTheme.id == "default")
    }

    @Test("Convenience accessors return non-nil tokens for light mode")
    @MainActor
    func convenienceAccessorsLight() {
        let provider = ThemeProvider()
        provider.colorScheme = .light

        // Colors
        let colors = provider.colors
        #expect(colors.avatarPalette.count == 10)

        // Typography — spot check a couple
        let typo = provider.typography
        // Font comparison is opaque, but we can verify the property exists
        _ = typo.displayLarge
        _ = typo.bodyMedium
        _ = typo.caption

        // Spacing
        let spacing = provider.spacing
        #expect(spacing.xxs == 2)
        #expect(spacing.lg == 16)
        #expect(spacing.avatarSize == 44)
        #expect(spacing.touchMinimum == 44)

        // Shapes
        let shapes = provider.shapes
        #expect(shapes.small == 8)
        #expect(shapes.medium == 12)
    }

    @Test("Convenience accessors return non-nil tokens for dark mode")
    @MainActor
    func convenienceAccessorsDark() {
        let provider = ThemeProvider()
        provider.colorScheme = .dark

        let colors = provider.colors
        #expect(colors.avatarPalette.count == 10)

        // Dark mode should suppress shadows
        let shapes = provider.shapes
        #expect(shapes.shadowSubtle.radius == 0)
        #expect(shapes.shadowMedium.radius == 0)
        #expect(shapes.shadowElevated.radius == 0)
    }

    @Test("Color scheme change updates colors and shapes",
          arguments: [ColorScheme.light, ColorScheme.dark])
    @MainActor
    func colorSchemeSwitch(scheme: ColorScheme) {
        let provider = ThemeProvider()
        provider.colorScheme = scheme

        // Should not crash, all tokens resolve
        _ = provider.colors.accent
        _ = provider.colors.textPrimary
        _ = provider.colors.destructive
        _ = provider.shapes.shadowMedium
    }

    @Test("Switching through all themes does not crash",
          arguments: ["default", "midnight", "forest", "sunset", "lavender", "rose"])
    @MainActor
    func switchAllThemes(themeId: String) {
        let provider = ThemeProvider()
        provider.apply(themeId)
        #expect(provider.currentTheme.id == themeId)

        // Resolve both color schemes
        provider.colorScheme = .light
        _ = provider.colors
        _ = provider.shapes

        provider.colorScheme = .dark
        _ = provider.colors
        _ = provider.shapes
    }
}

// MARK: - ThemeColors Completeness Tests

@Suite("ThemeColors")
struct ThemeColorsTests {

    @Test("All themes produce complete color tokens in light mode",
          arguments: ["default", "midnight", "forest", "sunset", "lavender", "rose"])
    func lightModeTokensComplete(themeId: String) {
        let theme = ThemeRegistry.theme(for: themeId)
        let colors = theme.colors(for: .light)

        // Backgrounds
        _ = colors.background
        _ = colors.surface
        _ = colors.surfaceElevated
        _ = colors.surfaceSelected
        _ = colors.surfaceHovered

        // Text
        _ = colors.textPrimary
        _ = colors.textSecondary
        _ = colors.textTertiary
        _ = colors.textInverse

        // Accent
        _ = colors.accent
        _ = colors.accentMuted
        _ = colors.accentHover

        // Semantic
        _ = colors.destructive
        _ = colors.destructiveMuted
        _ = colors.success
        _ = colors.successMuted
        _ = colors.warning
        _ = colors.warningMuted

        // Chrome
        _ = colors.separator
        _ = colors.border
        _ = colors.disabled
        _ = colors.shimmer

        // Categories
        _ = colors.categoryPrimary
        _ = colors.categorySocial
        _ = colors.categoryPromotions
        _ = colors.categoryUpdates
        _ = colors.categoryForums
        _ = colors.categoryUncategorized
        _ = colors.categoryPrimaryMuted
        _ = colors.categorySocialMuted
        _ = colors.categoryPromotionsMuted
        _ = colors.categoryUpdatesMuted
        _ = colors.categoryForumsMuted
        _ = colors.categoryUncategorizedMuted

        // Specialized
        _ = colors.unreadDot
        _ = colors.starred

        // AI
        _ = colors.aiAccent
        _ = colors.aiAccentMuted

        // Avatar palette
        #expect(colors.avatarPalette.count == 10)
    }

    @Test("All themes produce complete color tokens in dark mode",
          arguments: ["default", "midnight", "forest", "sunset", "lavender", "rose"])
    func darkModeTokensComplete(themeId: String) {
        let theme = ThemeRegistry.theme(for: themeId)
        let colors = theme.colors(for: .dark)

        // Spot check key dark-mode tokens exist
        _ = colors.background
        _ = colors.surface
        _ = colors.textPrimary
        _ = colors.accent
        _ = colors.destructive
        _ = colors.success
        _ = colors.warning
        _ = colors.aiAccent
        _ = colors.aiAccentMuted
        #expect(colors.avatarPalette.count == 10)
    }
}

// MARK: - ThemeTypography Tests

@Suite("ThemeTypography")
struct ThemeTypographyTests {

    @Test("Default typography provides all 14 font tokens")
    func allTokensExist() {
        let typo = ThemeTypography.default
        // Verify all 14 tokens are accessible (compile-time + runtime)
        _ = typo.displayLarge
        _ = typo.displaySmall
        _ = typo.titleLarge
        _ = typo.titleMedium
        _ = typo.titleSmall
        _ = typo.bodyLarge
        _ = typo.bodyMedium
        _ = typo.bodyMediumEmphasized
        _ = typo.bodySmall
        _ = typo.labelLarge
        _ = typo.labelMedium
        _ = typo.labelSmall
        _ = typo.caption
        _ = typo.captionMono
    }

    @Test("All themes share default typography",
          arguments: ["default", "midnight", "forest", "sunset", "lavender", "rose"])
    func allThemesUseDefaultTypography(themeId: String) {
        let theme = ThemeRegistry.theme(for: themeId)
        // All themes currently use .default typography.
        // We can't do Font equality but we can verify the property resolves.
        _ = theme.typography.displayLarge
        _ = theme.typography.bodyMedium
    }
}

// MARK: - ThemeSpacing Tests

@Suite("ThemeSpacing")
struct ThemeSpacingTests {

    @Test("Default spacing has correct base scale values")
    func baseScaleValues() {
        let s = ThemeSpacing.default
        #expect(s.xxs == 2)
        #expect(s.xs == 4)
        #expect(s.sm == 8)
        #expect(s.md == 12)
        #expect(s.lg == 16)
        #expect(s.xl == 20)
        #expect(s.xxl == 24)
        #expect(s.xxxl == 32)
    }

    @Test("Default spacing has correct component values")
    func componentValues() {
        let s = ThemeSpacing.default
        #expect(s.listRowVertical == 12)
        #expect(s.listRowHorizontal == 16)
        #expect(s.listRowSpacing == 10)
        #expect(s.sectionSpacing == 24)
        #expect(s.cardPadding == 16)
        #expect(s.avatarSize == 44)
        #expect(s.avatarSizeLarge == 56)
        #expect(s.avatarSizeSmall == 32)
        #expect(s.iconSize == 20)
        #expect(s.iconSizeSmall == 16)
        #expect(s.touchMinimum == 44)
        #expect(s.chipVertical == 6)
        #expect(s.chipHorizontal == 12)
        #expect(s.searchBarHeight == 36)
        #expect(s.bottomTabHeight == 56)
    }

    @Test("All themes share default spacing",
          arguments: ["default", "midnight", "forest", "sunset", "lavender", "rose"])
    func allThemesUseDefaultSpacing(themeId: String) {
        let theme = ThemeRegistry.theme(for: themeId)
        #expect(theme.spacing.lg == 16)
        #expect(theme.spacing.avatarSize == 44)
    }
}

// MARK: - ThemeShapes Tests

@Suite("ThemeShapes")
struct ThemeShapesTests {

    @Test("Default shapes have correct corner radii")
    func cornerRadii() {
        let shapes = ThemeShapes.default
        #expect(shapes.small == 8)
        #expect(shapes.medium == 12)
        #expect(shapes.large == 16)
        #expect(shapes.extraLarge == 20)
    }

    @Test("Default (light) shapes have non-zero shadows")
    func lightShadows() {
        let shapes = ThemeShapes.default
        #expect(shapes.shadowSubtle.radius == 2)
        #expect(shapes.shadowSubtle.y == 1)
        #expect(shapes.shadowMedium.radius == 4)
        #expect(shapes.shadowMedium.y == 2)
        #expect(shapes.shadowElevated.radius == 8)
        #expect(shapes.shadowElevated.y == 4)
    }

    @Test("Dark default shapes have zero-radius shadows")
    func darkShadows() {
        let shapes = ThemeShapes.darkDefault
        #expect(shapes.shadowSubtle.radius == 0)
        #expect(shapes.shadowMedium.radius == 0)
        #expect(shapes.shadowElevated.radius == 0)
    }

    @Test("VMShadowStyle.none has all-zero values")
    func shadowNone() {
        let none = VMShadowStyle.none
        #expect(none.radius == 0)
        #expect(none.x == 0)
        #expect(none.y == 0)
    }

    @Test("Light vs dark shapes differ in shadow behavior",
          arguments: ["default", "midnight", "forest", "sunset", "lavender", "rose"])
    func lightDarkShadowDifference(themeId: String) {
        let theme = ThemeRegistry.theme(for: themeId)

        let lightShapes = theme.shapes(for: .light)
        let darkShapes = theme.shapes(for: .dark)

        // Light mode should have non-zero shadows
        #expect(lightShapes.shadowMedium.radius > 0)
        // Dark mode should have zero shadows
        #expect(darkShapes.shadowMedium.radius == 0)
    }
}

// MARK: - SettingsStore Theme Integration Tests

@Suite("SettingsStore Theme Integration")
struct SettingsStoreThemeTests {

    @MainActor
    private static func makeStore() -> (SettingsStore, UserDefaults) {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = SettingsStore(defaults: defaults)
        return (store, defaults)
    }

    @Test("Default selectedThemeId is 'default'")
    @MainActor
    func defaultSelectedThemeId() {
        let (store, _) = Self.makeStore()
        #expect(store.selectedThemeId == "default")
    }

    @Test("selectedThemeId persists across instances")
    @MainActor
    func selectedThemeIdPersistence() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = SettingsStore(defaults: defaults)
        store1.selectedThemeId = "midnight"

        let store2 = SettingsStore(defaults: defaults)
        #expect(store2.selectedThemeId == "midnight")
    }

    @Test("resetAll restores selectedThemeId to default")
    @MainActor
    func resetAllRestoresThemeId() {
        let (store, _) = Self.makeStore()
        store.selectedThemeId = "forest"
        #expect(store.selectedThemeId == "forest")

        store.resetAll()
        #expect(store.selectedThemeId == "default")
    }

    @Test("ThemeProvider can be initialized from SettingsStore.selectedThemeId")
    @MainActor
    func providerFromSettingsStore() {
        let (store, _) = Self.makeStore()
        store.selectedThemeId = "sunset"

        let provider = ThemeProvider(themeId: store.selectedThemeId)
        #expect(provider.currentTheme.id == "sunset")
    }

    @Test("ThemeProvider.apply() mirrors SettingsStore update")
    @MainActor
    func providerMirrorsSettingsStore() {
        let (store, _) = Self.makeStore()
        let provider = ThemeProvider(themeId: store.selectedThemeId)

        // Simulate theme picker flow
        store.selectedThemeId = "lavender"
        provider.apply(store.selectedThemeId)

        #expect(provider.currentTheme.id == "lavender")
        #expect(store.selectedThemeId == "lavender")
    }
}

// MARK: - Individual Theme Identity Tests

@Suite("Theme Identity")
struct ThemeIdentityTests {

    @Test("DefaultTheme has correct metadata")
    func defaultThemeMetadata() {
        let theme = DefaultTheme()
        #expect(theme.id == "default")
        #expect(theme.displayName == "VaultMail")
    }

    @Test("MidnightTheme has correct metadata")
    func midnightThemeMetadata() {
        let theme = MidnightTheme()
        #expect(theme.id == "midnight")
        #expect(theme.displayName == "Midnight")
    }

    @Test("ForestTheme has correct metadata")
    func forestThemeMetadata() {
        let theme = ForestTheme()
        #expect(theme.id == "forest")
        #expect(theme.displayName == "Forest")
    }

    @Test("SunsetTheme has correct metadata")
    func sunsetThemeMetadata() {
        let theme = SunsetTheme()
        #expect(theme.id == "sunset")
        #expect(theme.displayName == "Sunset")
    }

    @Test("LavenderTheme has correct metadata")
    func lavenderThemeMetadata() {
        let theme = LavenderTheme()
        #expect(theme.id == "lavender")
        #expect(theme.displayName == "Lavender")
    }

    @Test("RoseTheme has correct metadata")
    func roseThemeMetadata() {
        let theme = RoseTheme()
        #expect(theme.id == "rose")
        #expect(theme.displayName == "Rose")
    }

    @Test("Each theme produces unique accent colors in light mode")
    func uniqueAccentColorsLight() {
        // Resolve the accent color descriptions for each theme to verify distinctness
        var accents: [String: String] = [:]
        for theme in ThemeRegistry.allThemes {
            let colors = theme.colors(for: .light)
            let description = "\(colors.accent)"
            accents[theme.id] = description
        }
        // All 6 should be unique
        let uniqueValues = Set(accents.values)
        #expect(uniqueValues.count == 6, "Expected 6 unique accent colors, got \(uniqueValues.count)")
    }
}
