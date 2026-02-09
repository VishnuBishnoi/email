import SwiftUI
import SwiftData
import PrivateMailFeature

@main
struct PrivateMailApp: App {
    let modelContainer: ModelContainer
    let settingsStore: SettingsStore
    let appLockManager: AppLockManager
    let manageAccounts: ManageAccountsUseCaseProtocol
    let fetchThreads: FetchThreadsUseCaseProtocol
    let manageThreadActions: ManageThreadActionsUseCaseProtocol
    let syncEmails: SyncEmailsUseCaseProtocol
    let composeEmail: ComposeEmailUseCaseProtocol
    let queryContacts: QueryContactsUseCaseProtocol

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

        let emailRepo = EmailRepositoryImpl(modelContainer: modelContainer)
        fetchThreads = FetchThreadsUseCase(repository: emailRepo)
        manageThreadActions = ManageThreadActionsUseCase(repository: emailRepo)
        composeEmail = ComposeEmailUseCase(repository: emailRepo)
        queryContacts = QueryContactsUseCase(repository: emailRepo)

        let connectionPool = ConnectionPool()
        syncEmails = SyncEmailsUseCase(
            accountRepository: accountRepo,
            emailRepository: emailRepo,
            keychainManager: keychainManager,
            connectionPool: connectionPool
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                manageAccounts: manageAccounts,
                fetchThreads: fetchThreads,
                manageThreadActions: manageThreadActions,
                syncEmails: syncEmails,
                composeEmail: composeEmail,
                queryContacts: queryContacts,
                appLockManager: appLockManager
            )
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
