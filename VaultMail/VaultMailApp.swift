import SwiftUI
import SwiftData
import VaultMailFeature

@main
struct VaultMailApp: App {
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
    let fts5Manager: FTS5Manager
    let vectorEngine: VectorSearchEngine
    let searchIndexManager: SearchIndexManager
    let searchUseCase: SearchEmailsUseCase

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

        // Search infrastructure (IOS-S-01..05)
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        fts5Manager = FTS5Manager(databaseDirectoryURL: appSupportDir)
        vectorEngine = VectorSearchEngine()
        searchIndexManager = SearchIndexManager(fts5Manager: fts5Manager, modelContainer: modelContainer)
        searchUseCase = SearchEmailsUseCase(fts5Manager: fts5Manager, vectorEngine: vectorEngine, modelContainer: modelContainer)

        aiProcessingQueue = AIProcessingQueue(
            categorize: categorizeUseCase,
            detectSpam: detectSpamUseCase,
            aiRepository: aiRepository,
            modelContainer: modelContainer,
            searchIndexManager: searchIndexManager,
            aiEngineResolver: aiEngineResolver
        )
        summarizeThread = SummarizeThreadUseCase(aiRepository: aiRepository)
        smartReply = SmartReplyUseCase(aiRepository: aiRepository)
    }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
            MacOSMainView(
                fetchThreads: fetchThreads,
                manageThreadActions: manageThreadActions,
                manageAccounts: manageAccounts,
                syncEmails: syncEmails,
                fetchEmailDetail: fetchEmailDetail,
                markRead: markRead,
                downloadAttachment: downloadAttachment,
                composeEmail: composeEmail,
                queryContacts: queryContacts,
                idleMonitor: idleMonitor,
                modelManager: aiModelManager,
                aiEngineResolver: aiEngineResolver,
                aiProcessingQueue: aiProcessingQueue,
                summarizeThread: summarizeThread,
                smartReply: smartReply,
                searchUseCase: searchUseCase
            )
            .environment(settingsStore)
            .task {
                await searchIndexManager.openIndex()
                await searchIndexManager.reindexIfNeeded()
            }
            #else
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
                smartReply: smartReply,
                searchUseCase: searchUseCase
            )
            .environment(settingsStore)
            .task {
                // Open FTS5 search database and backfill index on first launch
                await searchIndexManager.openIndex()
                await searchIndexManager.reindexIfNeeded()
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands { AppCommands() }
        #endif
        .modelContainer(modelContainer)

        #if os(macOS)
        Settings {
            MacSettingsView(
                manageAccounts: manageAccounts,
                modelManager: aiModelManager,
                aiEngineResolver: aiEngineResolver
            )
            .environment(settingsStore)
            .modelContainer(modelContainer)
        }
        #endif
    }
}
