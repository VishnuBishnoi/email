import SwiftUI

/// Shape and shadow tokens for the VaultMail theming engine.
///
/// Spec ref: FR-SH-01, FR-SH-02, FR-SH-03
public struct ThemeShapes: Sendable {

    // MARK: - Corner Radii

    /// 8pt — input fields, small cards, search bar.
    public let small: CGFloat
    /// 12pt — message bubbles, standard cards.
    public let medium: CGFloat
    /// 16pt — sheets, large cards, image previews.
    public let large: CGFloat
    /// 20pt — modals, onboarding cards.
    public let extraLarge: CGFloat

    // MARK: - Prebuilt Shapes (FR-SH-03)

    public var smallRect: RoundedRectangle { RoundedRectangle(cornerRadius: small) }
    public var mediumRect: RoundedRectangle { RoundedRectangle(cornerRadius: medium) }
    public var largeRect: RoundedRectangle { RoundedRectangle(cornerRadius: large) }
    public var capsuleShape: Capsule { Capsule() }

    // MARK: - Shadows (FR-SH-02)

    /// Light hover — black 4%, radius 2, y 1.
    public let shadowSubtle: VMShadowStyle
    /// Cards, message bubbles — black 8%, radius 4, y 2.
    public let shadowMedium: VMShadowStyle
    /// Sheets, modals — black 12%, radius 8, y 4.
    public let shadowElevated: VMShadowStyle

    /// Default shape values.
    public static let `default` = ThemeShapes(
        small: 8, medium: 12, large: 16, extraLarge: 20,
        shadowSubtle: .init(color: .black.opacity(0.04), radius: 2, x: 0, y: 1),
        shadowMedium: .init(color: .black.opacity(0.08), radius: 4, x: 0, y: 2),
        shadowElevated: .init(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    )

    /// Dark-mode shapes — shadows suppressed (OQ-2 resolved: suppress).
    public static let darkDefault = ThemeShapes(
        small: 8, medium: 12, large: 16, extraLarge: 20,
        shadowSubtle: .none,
        shadowMedium: .none,
        shadowElevated: .none
    )

    public init(
        small: CGFloat, medium: CGFloat, large: CGFloat, extraLarge: CGFloat,
        shadowSubtle: VMShadowStyle, shadowMedium: VMShadowStyle, shadowElevated: VMShadowStyle
    ) {
        self.small = small
        self.medium = medium
        self.large = large
        self.extraLarge = extraLarge
        self.shadowSubtle = shadowSubtle
        self.shadowMedium = shadowMedium
        self.shadowElevated = shadowElevated
    }
}

/// A shadow definition with color, radius, and offset.
///
/// Spec ref: FR-SH-02
public struct VMShadowStyle: Sendable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    /// No shadow (used in dark mode).
    public static let none = VMShadowStyle(color: .clear, radius: 0, x: 0, y: 0)

    public init(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

// MARK: - View Extension

extension View {
    /// Applies a `VMShadowStyle` to this view.
    public func vmShadow(_ style: VMShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
