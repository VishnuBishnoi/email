import Foundation

/// Spacing tokens for the VaultMail theming engine.
///
/// WhatsApp-inspired comfortable density: generous padding,
/// 44pt minimum touch targets, spacious list rows.
///
/// Spec ref: FR-SP-01, FR-SP-02
public struct ThemeSpacing: Sendable {

    // MARK: - Base Scale

    /// 2pt — inline icon gaps.
    public let xxs: CGFloat
    /// 4pt — tight internal padding.
    public let xs: CGFloat
    /// 8pt — between related elements.
    public let sm: CGFloat
    /// 12pt — default component padding.
    public let md: CGFloat
    /// 16pt — list row horizontal padding.
    public let lg: CGFloat
    /// 20pt — section spacing.
    public let xl: CGFloat
    /// 24pt — card padding, generous gaps.
    public let xxl: CGFloat
    /// 32pt — screen-level margins.
    public let xxxl: CGFloat

    // MARK: - Component-Specific

    /// 12pt — vertical padding per thread row.
    public let listRowVertical: CGFloat
    /// 16pt — horizontal padding per thread row.
    public let listRowHorizontal: CGFloat
    /// 10pt — gap between avatar and content in rows.
    public let listRowSpacing: CGFloat
    /// 24pt — vertical space between list sections.
    public let sectionSpacing: CGFloat
    /// 16pt — internal padding of cards / message bubbles.
    public let cardPadding: CGFloat
    /// 44pt — thread list avatar diameter.
    public let avatarSize: CGFloat
    /// 56pt — detail view, onboarding avatars.
    public let avatarSizeLarge: CGFloat
    /// 32pt — stacked / secondary avatars.
    public let avatarSizeSmall: CGFloat
    /// 20pt — standard icon size.
    public let iconSize: CGFloat
    /// 16pt — inline / caption icons.
    public let iconSizeSmall: CGFloat
    /// 44pt — minimum tap target per Apple HIG.
    public let touchMinimum: CGFloat
    /// 6pt — category chip vertical padding.
    public let chipVertical: CGFloat
    /// 12pt — category chip horizontal padding.
    public let chipHorizontal: CGFloat
    /// 36pt — search input field height.
    public let searchBarHeight: CGFloat
    /// 56pt — bottom tab bar total height.
    public let bottomTabHeight: CGFloat

    /// Default comfortable spacing values.
    public static let `default` = ThemeSpacing(
        xxs: 2, xs: 4, sm: 8, md: 12, lg: 16, xl: 20, xxl: 24, xxxl: 32,
        listRowVertical: 12, listRowHorizontal: 16, listRowSpacing: 10,
        sectionSpacing: 24, cardPadding: 16,
        avatarSize: 44, avatarSizeLarge: 56, avatarSizeSmall: 32,
        iconSize: 20, iconSizeSmall: 16, touchMinimum: 44,
        chipVertical: 6, chipHorizontal: 12,
        searchBarHeight: 36, bottomTabHeight: 56
    )

    public init(
        xxs: CGFloat, xs: CGFloat, sm: CGFloat, md: CGFloat,
        lg: CGFloat, xl: CGFloat, xxl: CGFloat, xxxl: CGFloat,
        listRowVertical: CGFloat, listRowHorizontal: CGFloat,
        listRowSpacing: CGFloat, sectionSpacing: CGFloat, cardPadding: CGFloat,
        avatarSize: CGFloat, avatarSizeLarge: CGFloat, avatarSizeSmall: CGFloat,
        iconSize: CGFloat, iconSizeSmall: CGFloat, touchMinimum: CGFloat,
        chipVertical: CGFloat, chipHorizontal: CGFloat,
        searchBarHeight: CGFloat, bottomTabHeight: CGFloat
    ) {
        self.xxs = xxs; self.xs = xs; self.sm = sm; self.md = md
        self.lg = lg; self.xl = xl; self.xxl = xxl; self.xxxl = xxxl
        self.listRowVertical = listRowVertical
        self.listRowHorizontal = listRowHorizontal
        self.listRowSpacing = listRowSpacing
        self.sectionSpacing = sectionSpacing
        self.cardPadding = cardPadding
        self.avatarSize = avatarSize
        self.avatarSizeLarge = avatarSizeLarge
        self.avatarSizeSmall = avatarSizeSmall
        self.iconSize = iconSize
        self.iconSizeSmall = iconSizeSmall
        self.touchMinimum = touchMinimum
        self.chipVertical = chipVertical
        self.chipHorizontal = chipHorizontal
        self.searchBarHeight = searchBarHeight
        self.bottomTabHeight = bottomTabHeight
    }
}
