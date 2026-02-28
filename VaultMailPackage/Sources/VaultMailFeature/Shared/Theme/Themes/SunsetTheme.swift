import SwiftUI

/// Sunset theme — warm amber / orange accent.
///
/// Light accent: `#C2410C` (WCAG AA ≥ 5.0:1 vs white)
/// Dark accent: `#FB923C`
///
/// Spec ref: FR-BT-01, FR-BT-04
public struct SunsetTheme: VaultMailTheme {
    public let id = "sunset"
    public let displayName = "Sunset"
    public let previewColor = Color(hex: 0xC2410C)

    public func colors(for scheme: ColorScheme) -> ThemeColors {
        let isDark = scheme == .dark
        return ThemeColorFactory.make(
            accent: isDark ? Color(hex: 0xFB923C) : Color(hex: 0xC2410C),
            accentMuted: (isDark ? Color(hex: 0xFB923C) : Color(hex: 0xC2410C))
                .opacity(isDark ? 0.15 : 0.12),
            accentHover: isDark ? Color(hex: 0xFDBA74) : Color(hex: 0x9A3412),
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
