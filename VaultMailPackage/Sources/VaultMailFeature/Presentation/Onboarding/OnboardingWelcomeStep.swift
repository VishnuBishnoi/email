import SwiftUI

/// Onboarding Step 1: Welcome screen with privacy value proposition.
///
/// Displays app logo, branding, and the core privacy message:
/// "Your emails stay on your device. No servers. No tracking. No compromise."
///
/// Spec ref: FR-OB-01 step 1
struct OnboardingWelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "envelope.shield.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("VaultMail")
                .font(.largeTitle.bold())

            Text("Your emails stay on your device.\nNo servers. No tracking.\nNo compromise.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    OnboardingWelcomeStep {
        // Continue action
    }
}
