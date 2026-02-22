import SwiftUI

/// Factory for building `ThemeColors` from an accent color.
///
/// All themes share backgrounds, text, status, and chrome tokens.
/// Only the accent family varies per theme (FR-BT-02, FR-BT-03).
///
/// Spec ref: FR-CO-01, FR-BT-02, FR-BT-03
enum ThemeColorFactory {

    /// Standard avatar palette — constant across all themes (OQ-3).
    static let avatarPalette: [Color] = [
        .blue, .green, .orange, .purple, .pink,
        .red, .teal, .indigo, .mint, .cyan,
    ]

    /// Builds a complete `ThemeColors` for a given accent + color scheme.
    static func make(
        accent: Color,
        accentMuted: Color,
        accentHover: Color,
        scheme: ColorScheme
    ) -> ThemeColors {
        let isDark = scheme == .dark

        return ThemeColors(
            // Backgrounds
            background: isDark ? Color(hex: 0x000000) : Color(hex: 0xFFFFFF),
            surface: isDark ? Color(hex: 0x1C1C1E) : Color(hex: 0xFFFFFF),
            surfaceElevated: isDark ? Color(hex: 0x2C2C2E) : Color(hex: 0xF2F2F7),
            surfaceSelected: accentMuted,

            // Text
            textPrimary: isDark ? .white : .black,
            textSecondary: Color(
                light: Color(hex: 0x636366),
                dark: Color.white.opacity(0.6)
            ),
            textTertiary: Color(
                light: Color(hex: 0x8E8E93),
                dark: Color.white.opacity(0.4)
            ),
            textInverse: .white,

            // Accent
            accent: accent,
            accentMuted: accentMuted,
            accentHover: accentHover,

            // Semantic Status
            destructive: isDark ? Color(hex: 0xFF453A) : Color(hex: 0xFF3B30),
            destructiveMuted: (isDark ? Color(hex: 0xFF453A) : Color(hex: 0xFF3B30))
                .opacity(isDark ? 0.15 : 0.12),
            success: isDark ? Color(hex: 0x30D158) : Color(hex: 0x34C759),
            successMuted: (isDark ? Color(hex: 0x30D158) : Color(hex: 0x34C759))
                .opacity(isDark ? 0.15 : 0.12),
            warning: isDark ? Color(hex: 0xFF9F0A) : Color(hex: 0xFF9500),
            warningMuted: (isDark ? Color(hex: 0xFF9F0A) : Color(hex: 0xFF9500))
                .opacity(isDark ? 0.15 : 0.12),

            // UI Chrome
            separator: isDark
                ? Color(hex: 0x545458).opacity(0.3)
                : Color(hex: 0x3C3C43).opacity(0.12),
            border: isDark
                ? Color(hex: 0x545458).opacity(0.4)
                : Color(hex: 0x3C3C43).opacity(0.18),
            disabled: isDark
                ? Color(hex: 0x545458).opacity(0.3)
                : Color(hex: 0x3C3C43).opacity(0.18),
            shimmer: isDark
                ? Color(hex: 0x545458).opacity(0.15)
                : Color(hex: 0x3C3C43).opacity(0.08),

            // AI Category Colors
            categoryPrimary: accent,
            categorySocial: isDark ? Color(hex: 0x30D158) : Color(hex: 0x34C759),
            categoryPromotions: isDark ? Color(hex: 0xFF9F0A) : Color(hex: 0xFF9500),
            categoryUpdates: isDark ? Color(hex: 0xBF5AF2) : Color(hex: 0xAF52DE),
            categoryForums: isDark ? Color(hex: 0x64D2FF) : Color(hex: 0x5AC8FA),
            categoryUncategorized: isDark
                ? Color.white.opacity(0.4)
                : Color(hex: 0x8E8E93),

            categoryPrimaryMuted: accentMuted,
            categorySocialMuted: (isDark ? Color(hex: 0x30D158) : Color(hex: 0x34C759))
                .opacity(isDark ? 0.15 : 0.12),
            categoryPromotionsMuted: (isDark ? Color(hex: 0xFF9F0A) : Color(hex: 0xFF9500))
                .opacity(isDark ? 0.15 : 0.12),
            categoryUpdatesMuted: (isDark ? Color(hex: 0xBF5AF2) : Color(hex: 0xAF52DE))
                .opacity(isDark ? 0.15 : 0.12),
            categoryForumsMuted: (isDark ? Color(hex: 0x64D2FF) : Color(hex: 0x5AC8FA))
                .opacity(isDark ? 0.15 : 0.12),
            categoryUncategorizedMuted: isDark
                ? Color(hex: 0x545458).opacity(0.15)
                : Color(hex: 0x3C3C43).opacity(0.08),

            // Specialized
            unreadDot: accent,
            starred: Color(hex: 0xFFD60A),

            // AI
            aiAccent: isDark ? Color(hex: 0xBF5AF2) : Color(hex: 0xAF52DE),
            aiAccentMuted: (isDark ? Color(hex: 0xBF5AF2) : Color(hex: 0xAF52DE))
                .opacity(isDark ? 0.15 : 0.12),

            // Avatar
            avatarPalette: avatarPalette
        )
    }
}

// MARK: - Color Hex Init

extension Color {
    /// Creates a Color from a hex integer (e.g., `0xFF3B30`).
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// Creates a Color that resolves to `light` or `dark` based on color scheme.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(dark)
                : NSColor(light)
        })
        #endif
    }
}
