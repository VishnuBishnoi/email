import SwiftUI

/// Forest theme — emerald green accent, privacy / trust feel.
///
/// Light accent: `#047857` (WCAG AA ≥ 5.0:1 vs white)
/// Dark accent: `#34D399`
///
/// Spec ref: FR-BT-01, FR-BT-04
public struct ForestTheme: VaultMailTheme {
    public let id = "forest"
    public let displayName = "Forest"
    public let previewColor = Color(hex: 0x047857)

    public func colors(for scheme: ColorScheme) -> ThemeColors {
        let isDark = scheme == .dark
        return ThemeColorFactory.make(
            accent: isDark ? Color(hex: 0x34D399) : Color(hex: 0x047857),
            accentMuted: (isDark ? Color(hex: 0x34D399) : Color(hex: 0x047857))
                .opacity(isDark ? 0.15 : 0.12),
            accentHover: isDark ? Color(hex: 0x6EE7B7) : Color(hex: 0x065F46),
            scheme: scheme
        )
    }

    public let typography: ThemeTypography = .default
    public let spacing: ThemeSpacing = .default

    public func shapes(for scheme: ColorScheme) -> ThemeShapes {
        scheme == .dark ? .darkDefault : .default
    }

    public init() {}
}
