import SwiftUI

/// Root onboarding container with 5-step forward-only navigation.
///
/// Presented on first launch when no accounts are configured, or when all
/// accounts are removed. Uses @State for step index and progress dots.
///
/// Spec ref: FR-OB-01, G-04 (5 or fewer steps)
public struct OnboardingView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ThemeProvider.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let manageAccounts: ManageAccountsUseCaseProtocol
    let syncEmails: SyncEmailsUseCaseProtocol
    let modelManager: ModelManager
    var aiEngineResolver: AIEngineResolver?
    var providerDiscovery: ProviderDiscovery?
    var connectionTestUseCase: ConnectionTestUseCaseProtocol?

    @State private var currentStep = 0
    @State private var addedAccounts: [Account] = []
    @State private var appLockEnabled = false

    private let totalSteps = 5

    public init(
        manageAccounts: ManageAccountsUseCaseProtocol,
        syncEmails: SyncEmailsUseCaseProtocol,
        modelManager: ModelManager = ModelManager(),
        aiEngineResolver: AIEngineResolver? = nil,
        providerDiscovery: ProviderDiscovery? = nil,
        connectionTestUseCase: ConnectionTestUseCaseProtocol? = nil
    ) {
        self.manageAccounts = manageAccounts
        self.syncEmails = syncEmails
        self.modelManager = modelManager
        self.aiEngineResolver = aiEngineResolver
        self.providerDiscovery = providerDiscovery
        self.connectionTestUseCase = connectionTestUseCase
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Progress dots (G-04)
            ProgressDotsView(currentStep: currentStep, totalSteps: totalSteps)
                .padding(.top, theme.spacing.lg)
                .padding(.bottom, theme.spacing.sm)

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
                        addedAccounts: $addedAccounts,
                        providerDiscovery: providerDiscovery,
                        connectionTestUseCase: connectionTestUseCase
                    ) {
                        advanceStep()
                    }
                case 2:
                    OnboardingSecurityStep(appLockEnabled: $appLockEnabled) {
                        advanceStep()
                    }
                case 3:
                    OnboardingAIModelStep(
                        modelManager: modelManager,
                        aiEngineResolver: aiEngineResolver,
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

        // Initial IMAP sync is handled by ThreadListView.initialLoad() — no need
        // to duplicate here. ThreadListView uses syncAccountInboxFirst() which
        // provides progressive UI feedback as inbox arrives first.
    }
}

// MARK: - Progress Dots

/// Horizontal progress indicator dots for onboarding steps.
struct ProgressDotsView: View {
    @Environment(ThemeProvider.self) private var theme
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: theme.spacing.sm) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index <= currentStep ? theme.colors.accent : theme.colors.textSecondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentStep + 1) of \(totalSteps)")
    }
}
