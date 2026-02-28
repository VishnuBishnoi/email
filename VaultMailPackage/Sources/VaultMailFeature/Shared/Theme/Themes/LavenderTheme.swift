import SwiftUI

/// Lavender theme — creative, modern purple accent.
///
/// Light accent: `#9333EA` (WCAG AA ≥ 4.6:1 vs white)
/// Dark accent: `#C084FC`
///
/// Spec ref: FR-BT-01, FR-BT-04
public struct LavenderTheme: VaultMailTheme {
    public let id = "lavender"
    public let displayName = "Lavender"
    public let previewColor = Color(hex: 0x9333EA)

    public func colors(for scheme: ColorScheme) -> ThemeColors {
        let isDark = scheme == .dark
        return ThemeColorFactory.make(
            accent: isDark ? Color(hex: 0xC084FC) : Color(hex: 0x9333EA),
            accentMuted: (isDark ? Color(hex: 0xC084FC) : Color(hex: 0x9333EA))
                .opacity(isDark ? 0.15 : 0.12),
            accentHover: isDark ? Color(hex: 0xD8B4FE) : Color(hex: 0x7E22CE),
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
