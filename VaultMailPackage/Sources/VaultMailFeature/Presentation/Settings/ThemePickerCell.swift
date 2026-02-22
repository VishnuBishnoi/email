import SwiftUI

/// A single theme preview cell showing a colored circle, name, and checkmark.
///
/// Used inside the theme picker grid in Settings > Appearance.
/// Tapping selects the theme immediately.
///
/// Spec ref: FR-SET-02
struct ThemePickerCell: View {
    let theme: any VaultMailTheme
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(ThemeProvider.self) private var themeProvider

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: themeProvider.spacing.sm) {
                Circle()
                    .fill(theme.previewColor)
                    .frame(width: themeProvider.spacing.avatarSize, height: themeProvider.spacing.avatarSize)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(themeProvider.typography.titleSmall)
                                .foregroundStyle(themeProvider.colors.textInverse)
                        }
                    }
                    .overlay {
                        Circle()
                            .stroke(
                                isSelected ? themeProvider.colors.accent : themeProvider.colors.border,
                                lineWidth: isSelected ? 2.5 : 0.5
                            )
                    }

                Text(theme.displayName)
                    .font(themeProvider.typography.caption)
                    .foregroundStyle(themeProvider.colors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.displayName) theme\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

#Preview("Selected") {
    ThemePickerCell(
        theme: DefaultTheme(),
        isSelected: true,
        onSelect: {}
    )
    .environment(ThemeProvider())
    .padding()
}

#Preview("Not Selected") {
    ThemePickerCell(
        theme: MidnightTheme(),
        isSelected: false,
        onSelect: {}
    )
    .environment(ThemeProvider())
    .padding()
}
