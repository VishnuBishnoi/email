import SwiftUI

/// Onboarding Step 3: Security recommendations.
///
/// Displays "Protect your data" screen with 5 security recommendations
/// per Proposal Section 6.4. Includes an optional toggle to enable app lock.
/// On macOS, additionally recommends FileVault enablement.
///
/// Spec ref: FR-OB-01 step 3, Proposal Section 6.4, Foundation Section 9.2
struct OnboardingSecurityStep: View {
    @Binding var appLockEnabled: Bool
    let onNext: () -> Void

    @Environment(ThemeProvider.self) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.xl) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(theme.colors.accent)
                .accessibilityHidden(true)

            Text("Protect your data")
                .font(theme.typography.displaySmall)

            Text("We recommend these steps to keep your email secure.")
                .font(theme.typography.bodyLarge)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: theme.spacing.lg) {
                SecurityRecommendationRow(
                    icon: "faceid",
                    text: "Enable device passcode and biometric authentication"
                )
                SecurityRecommendationRow(
                    icon: "lock.shield",
                    text: "Enable app lock for additional privacy"
                )
                SecurityRecommendationRow(
                    icon: "externaldrive.badge.checkmark",
                    text: "Use encrypted backups"
                )
                SecurityRecommendationRow(
                    icon: "arrow.triangle.2.circlepath",
                    text: "Keep your device OS updated"
                )
                SecurityRecommendationRow(
                    icon: "person.crop.circle.badge.checkmark",
                    text: "Review connected accounts periodically"
                )
                #if os(macOS)
                SecurityRecommendationRow(
                    icon: "lock.desktopcomputer",
                    text: "Enable FileVault for full-disk encryption"
                )
                #endif
            }
            .padding(.horizontal)

            // Optional app lock toggle (FR-OB-01 step 3)
            Toggle("Enable App Lock", isOn: $appLockEnabled)
                .padding(.horizontal)
                .tint(theme.colors.accent)

            Spacer()

            Button("Next") {
                onNext()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, theme.spacing.xxxl)
        .padding(.bottom, 40)
    }
}

/// A single security recommendation row with icon and text.
struct SecurityRecommendationRow: View {
    let icon: String
    let text: String

    @Environment(ThemeProvider.self) private var theme

    var body: some View {
        HStack(spacing: theme.spacing.md) {
            Image(systemName: icon)
                .font(theme.typography.titleLarge)
                .foregroundStyle(theme.colors.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(theme.typography.bodyLarge)
                .foregroundStyle(theme.colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    @Previewable @State var appLock = false
    OnboardingSecurityStep(appLockEnabled: $appLock) {
        // Next
    }
    .environment(ThemeProvider())
}
