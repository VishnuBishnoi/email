import SwiftUI

/// Root onboarding container with 5-step forward-only navigation.
///
/// Presented on first launch when no accounts are configured, or when all
/// accounts are removed. Uses @State for step index and progress dots.
///
/// Spec ref: FR-OB-01, G-04 (5 or fewer steps)
public struct OnboardingView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let manageAccounts: ManageAccountsUseCaseProtocol

    @State private var currentStep = 0
    @State private var addedAccounts: [Account] = []
    @State private var appLockEnabled = false

    private let totalSteps = 5

    public init(manageAccounts: ManageAccountsUseCaseProtocol) {
        self.manageAccounts = manageAccounts
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Progress dots (G-04)
            ProgressDotsView(currentStep: currentStep, totalSteps: totalSteps)
                .padding(.top, 16)
                .padding(.bottom, 8)

            // Step content
            Group {
                switch currentStep {
                case 0:
                    OnboardingWelcomeStep {
                        advanceStep()
                    }
                case 1:
                    OnboardingAccountStep(
                        manageAccounts: manageAccounts,
                        addedAccounts: $addedAccounts
                    ) {
                        advanceStep()
                    }
                case 2:
                    OnboardingSecurityStep(appLockEnabled: $appLockEnabled) {
                        advanceStep()
                    }
                case 3:
                    OnboardingAIModelStep(
                        onNext: { advanceStep() },
                        onSkip: { advanceStep() }
                    )
                case 4:
                    OnboardingReadyStep {
                        completeOnboarding()
                    }
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(reduceMotion ? .opacity : .slide)
            .animation(reduceMotion ? .easeInOut(duration: 0.3) : .default, value: currentStep)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Onboarding, step \(currentStep + 1) of \(totalSteps)")
    }

    // MARK: - Actions

    private func advanceStep() {
        guard currentStep < totalSteps - 1 else { return }
        currentStep += 1
    }

    private func completeOnboarding() {
        // Apply app lock preference if enabled during onboarding
        settingsStore.appLockEnabled = appLockEnabled

        // Set default notification preferences for added accounts (default: on)
        for account in addedAccounts {
            settingsStore.notificationPreferences[account.id] = true
        }

        // Set default sending account to first added account
        if let firstAccount = addedAccounts.first {
            settingsStore.defaultSendingAccountId = firstAccount.id
        }

        // Mark onboarding complete — do not re-display on subsequent launches
        settingsStore.isOnboardingComplete = true

        // PARTIAL SCOPE: Initial sync trigger deferred (Email Sync FR-SYNC-01).
        // The sync engine (Data/Sync/) does not exist yet — blocked on IOS-F-05/F-06.
        // When implemented, this MUST call:
        //   for account in addedAccounts { syncEngine.startInitialSync(for: account) }
        // Until then, onboarding completes without triggering sync.
        // Tracked in: https://github.com/VishnuBishnoi/email/issues (Email Sync epic)
    }
}

// MARK: - Progress Dots

/// Horizontal progress indicator dots for onboarding steps.
struct ProgressDotsView: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep + 1) of \(totalSteps)")
    }
}
