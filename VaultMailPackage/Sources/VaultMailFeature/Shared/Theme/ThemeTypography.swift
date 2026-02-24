import SwiftUI

/// Typography tokens for the VaultMail theming engine.
///
/// All tokens use SF Pro Rounded (system rounded design) via
/// `Font.system(size:weight:design:)`.
/// Dynamic Type scaling is automatic since we use `Font.system()`.
///
/// Spec ref: FR-TY-01, FR-TY-02, FR-TY-03
public struct ThemeTypography: Sendable {

    /// 34pt bold — onboarding hero text.
    public let displayLarge: Font
    /// 28pt bold — screen titles.
    public let displaySmall: Font
    /// 22pt semibold — section headers.
    public let titleLarge: Font
    /// 17pt semibold — sender names (unread), card titles.
    public let titleMedium: Font
    /// 15pt semibold — sub-section headers.
    public let titleSmall: Font
    /// 17pt regular — email body, primary content.
    public let bodyLarge: Font
    /// 15pt regular — subject lines, sender names (read).
    public let bodyMedium: Font
    /// 15pt medium — unread subject lines (explicit emphasis token).
    public let bodyMediumEmphasized: Font
    /// 13pt regular — snippets, secondary content.
    public let bodySmall: Font
    /// 15pt medium — button labels.
    public let labelLarge: Font
    /// 13pt medium — tab labels, chip text.
    public let labelMedium: Font
    /// 11pt medium — badge text, overline text.
    public let labelSmall: Font
    /// 12pt regular — timestamps, metadata.
    public let caption: Font
    /// 12pt regular monospaced — technical details, IDs.
    public let captionMono: Font

    /// Default typography using SF Pro Rounded system fonts.
    public static let `default` = ThemeTypography(
        displayLarge: .system(size: 34, weight: .bold, design: .rounded),
        displaySmall: .system(size: 28, weight: .bold, design: .rounded),
        titleLarge: .system(size: 22, weight: .semibold, design: .rounded),
        titleMedium: .system(size: 17, weight: .semibold, design: .rounded),
        titleSmall: .system(size: 15, weight: .semibold, design: .rounded),
        bodyLarge: .system(size: 17, weight: .regular, design: .rounded),
        bodyMedium: .system(size: 15, weight: .regular, design: .rounded),
        bodyMediumEmphasized: .system(size: 15, weight: .medium, design: .rounded),
        bodySmall: .system(size: 13, weight: .regular, design: .rounded),
        labelLarge: .system(size: 15, weight: .medium, design: .rounded),
        labelMedium: .system(size: 13, weight: .medium, design: .rounded),
        labelSmall: .system(size: 11, weight: .medium, design: .rounded),
        caption: .system(size: 12, weight: .regular, design: .rounded),
        captionMono: .system(size: 12, weight: .regular, design: .monospaced)
    )

    public init(
        displayLarge: Font,
        displaySmall: Font,
        titleLarge: Font,
        titleMedium: Font,
        titleSmall: Font,
        bodyLarge: Font,
        bodyMedium: Font,
        bodyMediumEmphasized: Font,
        bodySmall: Font,
        labelLarge: Font,
        labelMedium: Font,
        labelSmall: Font,
        caption: Font,
        captionMono: Font
    ) {
        self.displayLarge = displayLarge
        self.displaySmall = displaySmall
        self.titleLarge = titleLarge
        self.titleMedium = titleMedium
        self.titleSmall = titleSmall
        self.bodyLarge = bodyLarge
        self.bodyMedium = bodyMedium
        self.bodyMediumEmphasized = bodyMediumEmphasized
        self.bodySmall = bodySmall
        self.labelLarge = labelLarge
        self.labelMedium = labelMedium
        self.labelSmall = labelSmall
        self.caption = caption
        self.captionMono = captionMono
    }

    /// Returns typography scaled by a global user-selected factor.
    public func scaled(by factor: CGFloat) -> ThemeTypography {
        ThemeTypography(
            displayLarge: .system(size: 34 * factor, weight: .bold, design: .rounded),
            displaySmall: .system(size: 28 * factor, weight: .bold, design: .rounded),
            titleLarge: .system(size: 22 * factor, weight: .semibold, design: .rounded),
            titleMedium: .system(size: 17 * factor, weight: .semibold, design: .rounded),
            titleSmall: .system(size: 15 * factor, weight: .semibold, design: .rounded),
            bodyLarge: .system(size: 17 * factor, weight: .regular, design: .rounded),
            bodyMedium: .system(size: 15 * factor, weight: .regular, design: .rounded),
            bodyMediumEmphasized: .system(size: 15 * factor, weight: .medium, design: .rounded),
            bodySmall: .system(size: 13 * factor, weight: .regular, design: .rounded),
            labelLarge: .system(size: 15 * factor, weight: .medium, design: .rounded),
            labelMedium: .system(size: 13 * factor, weight: .medium, design: .rounded),
            labelSmall: .system(size: 11 * factor, weight: .medium, design: .rounded),
            caption: .system(size: 12 * factor, weight: .regular, design: .rounded),
            captionMono: .system(size: 12 * factor, weight: .regular, design: .monospaced)
        )
    }
}
