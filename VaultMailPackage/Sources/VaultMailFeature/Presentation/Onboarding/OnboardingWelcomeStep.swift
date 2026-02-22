import SwiftUI

/// Onboarding Step 1: Welcome screen with privacy value proposition.
///
/// Displays app logo, branding, and the core privacy message:
/// "Your emails stay on your device. No servers. No tracking. No compromise."
///
/// Spec ref: FR-OB-01 step 1
struct OnboardingWelcomeStep: View {
    let onContinue: () -> Void

    @Environment(ThemeProvider.self) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.xxl) {
            Spacer()

            Image(systemName: "envelope.shield.fill")
                .font(.system(size: 80))
                .foregroundStyle(theme.colors.accent)
                .accessibilityHidden(true)

            Text("VaultMail")
                .font(theme.typography.displayLarge)

            Text("Your emails stay on your device.\nNo servers. No tracking.\nNo compromise.")
                .font(theme.typography.titleLarge)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.colors.textSecondary)

            Spacer()

            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, theme.spacing.xxxl)
        .padding(.bottom, 40)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    OnboardingWelcomeStep {
        // Continue action
    }
    .environment(ThemeProvider())
}
