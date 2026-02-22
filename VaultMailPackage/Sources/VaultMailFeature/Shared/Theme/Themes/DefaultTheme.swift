import SwiftUI

/// VaultMail default theme — cerulean ocean blue.
///
/// Light accent: `#1B7A9E` (WCAG AA ≥ 4.6:1 vs white)
/// Dark accent: `#3DAED4`
///
/// Spec ref: FR-BT-01, FR-BT-04
public struct DefaultTheme: VaultMailTheme {
    public let id = "default"
    public let displayName = "VaultMail"
    public let previewColor = Color(hex: 0x1B7A9E)

    public func colors(for scheme: ColorScheme) -> ThemeColors {
        let isDark = scheme == .dark
        return ThemeColorFactory.make(
            accent: isDark ? Color(hex: 0x3DAED4) : Color(hex: 0x1B7A9E),
            accentMuted: (isDark ? Color(hex: 0x3DAED4) : Color(hex: 0x1B7A9E))
                .opacity(isDark ? 0.15 : 0.12),
            accentHover: isDark ? Color(hex: 0x4BC2E8) : Color(hex: 0x155F7A),
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
