import SwiftUI

/// Rose theme — bold, vibrant pink-red accent.
///
/// Light accent: `#E11D48` (WCAG AA ≥ 4.5:1 vs white)
/// Dark accent: `#FB7185`
///
/// Spec ref: FR-BT-01, FR-BT-04
public struct RoseTheme: VaultMailTheme {
    public let id = "rose"
    public let displayName = "Rose"
    public let previewColor = Color(hex: 0xE11D48)

    public func colors(for scheme: ColorScheme) -> ThemeColors {
        let isDark = scheme == .dark
        return ThemeColorFactory.make(
            accent: isDark ? Color(hex: 0xFB7185) : Color(hex: 0xE11D48),
            accentMuted: (isDark ? Color(hex: 0xFB7185) : Color(hex: 0xE11D48))
                .opacity(isDark ? 0.15 : 0.12),
            accentHover: isDark ? Color(hex: 0xFDA4AF) : Color(hex: 0xBE123C),
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
