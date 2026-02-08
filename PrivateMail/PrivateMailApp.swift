import SwiftUI
import SwiftData
import PrivateMailFeature

@main
struct PrivateMailApp: App {
    let modelContainer: ModelContainer
    let settingsStore: SettingsStore
    let appLockManager: AppLockManager
    let manageAccounts: ManageAccountsUseCaseProtocol

    init() {
        do {
            modelContainer = try ModelContainerFactory.create()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        settingsStore = SettingsStore()
        appLockManager = AppLockManager()

        let keychainManager = KeychainManager()
        let oauthManager = OAuthManager(clientId: AppConstants.oauthClientId)
        let accountRepo = AccountRepositoryImpl(
            modelContainer: modelContainer,
            keychainManager: keychainManager,
            oauthManager: oauthManager
        )
        manageAccounts = ManageAccountsUseCase(
            repository: accountRepo,
            oauthManager: oauthManager,
            keychainManager: keychainManager
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(manageAccounts: manageAccounts, appLockManager: appLockManager)
                .environment(settingsStore)
        }
        .modelContainer(modelContainer)

        #if os(macOS)
        Settings {
            SettingsView(manageAccounts: manageAccounts)
                .environment(settingsStore)
                .modelContainer(modelContainer)
        }
        #endif
    }
}
