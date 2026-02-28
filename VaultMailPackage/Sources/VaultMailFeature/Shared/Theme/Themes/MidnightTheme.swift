import SwiftUI

/// Midnight theme — deep indigo accent.
///
/// Light accent: `#4F46E5` (WCAG AA ≥ 5.2:1 vs white)
/// Dark accent: `#818CF8`
///
/// Spec ref: FR-BT-01, FR-BT-04
public struct MidnightTheme: VaultMailTheme {
    public let id = "midnight"
    public let displayName = "Midnight"
    public let previewColor = Color(hex: 0x4F46E5)

    public func colors(for scheme: ColorScheme) -> ThemeColors {
        let isDark = scheme == .dark
        return ThemeColorFactory.make(
            accent: isDark ? Color(hex: 0x818CF8) : Color(hex: 0x4F46E5),
            accentMuted: (isDark ? Color(hex: 0x818CF8) : Color(hex: 0x4F46E5))
                .opacity(isDark ? 0.15 : 0.12),
            accentHover: isDark ? Color(hex: 0xA5B4FC) : Color(hex: 0x4338CA),
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
