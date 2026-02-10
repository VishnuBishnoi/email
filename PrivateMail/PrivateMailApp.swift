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
    let fetchEmailDetail: FetchEmailDetailUseCaseProtocol
    let markRead: MarkReadUseCaseProtocol
    let downloadAttachment: DownloadAttachmentUseCaseProtocol
    let composeEmail: ComposeEmailUseCaseProtocol
    let queryContacts: QueryContactsUseCaseProtocol
    let idleMonitor: IDLEMonitorUseCaseProtocol
    let backgroundSyncScheduler: BackgroundSyncScheduler
    let aiModelManager: ModelManager
    let aiEngineResolver: AIEngineResolver
    let aiProcessingQueue: AIProcessingQueue
    let summarizeThread: SummarizeThreadUseCase
    let smartReply: SmartReplyUseCase

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

        let emailRepo = EmailRepositoryImpl(modelContainer: modelContainer)
        let connectionPool = ConnectionPool()

        manageAccounts = ManageAccountsUseCase(
            repository: accountRepo,
            oauthManager: oauthManager,
            keychainManager: keychainManager,
            connectionProvider: connectionPool
        )

        fetchEmailDetail = FetchEmailDetailUseCase(repository: emailRepo)
        markRead = MarkReadUseCase(repository: emailRepo)
        downloadAttachment = DownloadAttachmentUseCase(
            repository: emailRepo,
            connectionProvider: connectionPool,
            accountRepository: accountRepo,
            keychainManager: keychainManager
        )

        fetchThreads = FetchThreadsUseCase(repository: emailRepo)
        manageThreadActions = ManageThreadActionsUseCase(
            repository: emailRepo,
            connectionProvider: connectionPool,
            accountRepository: accountRepo,
            keychainManager: keychainManager
        )
        composeEmail = ComposeEmailUseCase(
            repository: emailRepo,
            accountRepository: accountRepo,
            keychainManager: keychainManager,
            smtpClient: SMTPClient()
        )
        queryContacts = QueryContactsUseCase(repository: emailRepo)

        syncEmails = SyncEmailsUseCase(
            accountRepository: accountRepo,
            emailRepository: emailRepo,
            keychainManager: keychainManager,
            connectionPool: connectionPool
        )

        idleMonitor = IDLEMonitorUseCase(
            connectionProvider: connectionPool,
            accountRepository: accountRepo,
            keychainManager: keychainManager
        )

        backgroundSyncScheduler = BackgroundSyncScheduler(
            syncEmails: syncEmails,
            manageAccounts: manageAccounts
        )
        backgroundSyncScheduler.registerTasks()
        backgroundSyncScheduler.scheduleNextSync()

        aiModelManager = ModelManager()

        // AI engine resolver + classification pipeline
        aiEngineResolver = AIEngineResolver(modelManager: aiModelManager)
        let categorizeUseCase = CategorizeEmailUseCase(engineResolver: aiEngineResolver)
        let detectSpamUseCase = DetectSpamUseCase(engineResolver: aiEngineResolver)
        // AI summary + smart reply use cases
        let aiRepository = AIRepositoryImpl(engineResolver: aiEngineResolver)

        aiProcessingQueue = AIProcessingQueue(
            categorize: categorizeUseCase,
            detectSpam: detectSpamUseCase,
            aiRepository: aiRepository,
            modelContainer: modelContainer
        )
        summarizeThread = SummarizeThreadUseCase(aiRepository: aiRepository)
        smartReply = SmartReplyUseCase(aiRepository: aiRepository)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                manageAccounts: manageAccounts,
                fetchThreads: fetchThreads,
                manageThreadActions: manageThreadActions,
                syncEmails: syncEmails,
                fetchEmailDetail: fetchEmailDetail,
                markRead: markRead,
                downloadAttachment: downloadAttachment,
                composeEmail: composeEmail,
                queryContacts: queryContacts,
                idleMonitor: idleMonitor,
                appLockManager: appLockManager,
                modelManager: aiModelManager,
                aiEngineResolver: aiEngineResolver,
                aiProcessingQueue: aiProcessingQueue,
                summarizeThread: summarizeThread,
                smartReply: smartReply
            )
            .environment(settingsStore)
        }
        .modelContainer(modelContainer)

        #if os(macOS)
        Settings {
            SettingsView(manageAccounts: manageAccounts, modelManager: aiModelManager)
                .environment(settingsStore)
                .modelContainer(modelContainer)
        }
        #endif
    }
}
