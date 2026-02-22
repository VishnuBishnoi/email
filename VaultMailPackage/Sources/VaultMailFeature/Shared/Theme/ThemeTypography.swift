import SwiftUI

/// Typography tokens for the VaultMail theming engine.
///
/// All tokens use SF Pro (system font) via `Font.system(size:weight:design:)`.
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

    /// Default typography using SF Pro system fonts.
    public static let `default` = ThemeTypography(
        displayLarge: .system(size: 34, weight: .bold),
        displaySmall: .system(size: 28, weight: .bold),
        titleLarge: .system(size: 22, weight: .semibold),
        titleMedium: .system(size: 17, weight: .semibold),
        titleSmall: .system(size: 15, weight: .semibold),
        bodyLarge: .system(size: 17, weight: .regular),
        bodyMedium: .system(size: 15, weight: .regular),
        bodyMediumEmphasized: .system(size: 15, weight: .medium),
        bodySmall: .system(size: 13, weight: .regular),
        labelLarge: .system(size: 15, weight: .medium),
        labelMedium: .system(size: 13, weight: .medium),
        labelSmall: .system(size: 11, weight: .medium),
        caption: .system(size: 12, weight: .regular),
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
}
