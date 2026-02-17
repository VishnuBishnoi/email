import SwiftUI
import SwiftData
import VaultMailFeature

@main @MainActor
struct VaultMailApp: App {
    /// Holds all app dependencies. `nil` when ModelContainer creation fails.
    private let dependencies: AppDependencies?
    /// Error message when database initialisation fails.
    private let containerError: String?

    init() {
        do {
            let container = try ModelContainerFactory.create()
            dependencies = AppDependencies(modelContainer: container)
            containerError = nil
        } catch {
            dependencies = nil
            containerError = error.localizedDescription
        }
    }

    var body: some Scene {
        mainWindowScene
        #if os(macOS)
        settingsScene
        #endif
    }

    private var mainWindowScene: some Scene {
        WindowGroup {
            if let deps = dependencies {
                mainView(deps: deps)
            } else {
                DatabaseErrorView(message: containerError ?? "Unknown error")
            }
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentMinSize)
        .commands { AppCommands() }
        #endif
    }

    #if os(macOS)
    private var settingsScene: some Scene {
        Settings {
            if let deps = dependencies {
                MacSettingsView(
                    manageAccounts: deps.manageAccounts,
                    modelManager: deps.aiModelManager,
                    aiEngineResolver: deps.aiEngineResolver
                )
                .environment(deps.settingsStore)
                .modelContainer(deps.modelContainer)
            }
        }
    }
    #endif

    @ViewBuilder
    private func mainView(deps: AppDependencies) -> some View {
        #if os(macOS)
        MacOSMainView(
            fetchThreads: deps.fetchThreads,
            manageThreadActions: deps.manageThreadActions,
            manageAccounts: deps.manageAccounts,
            syncEmails: deps.syncEmails,
            fetchEmailDetail: deps.fetchEmailDetail,
            markRead: deps.markRead,
            downloadAttachment: deps.downloadAttachment,
            composeEmail: deps.composeEmail,
            queryContacts: deps.queryContacts,
            idleMonitor: deps.idleMonitor,
            modelManager: deps.aiModelManager,
            aiEngineResolver: deps.aiEngineResolver,
            aiProcessingQueue: deps.aiProcessingQueue,
            summarizeThread: deps.summarizeThread,
            smartReply: deps.smartReply,
            searchUseCase: deps.searchUseCase
        )
        .environment(deps.settingsStore)
        .modelContainer(deps.modelContainer)
        .task {
            await deps.searchIndexManager.openIndex()
            await deps.searchIndexManager.reindexIfNeeded()
        }
        #else
        ContentView(
            manageAccounts: deps.manageAccounts,
            fetchThreads: deps.fetchThreads,
            manageThreadActions: deps.manageThreadActions,
            syncEmails: deps.syncEmails,
            fetchEmailDetail: deps.fetchEmailDetail,
            markRead: deps.markRead,
            downloadAttachment: deps.downloadAttachment,
            composeEmail: deps.composeEmail,
            queryContacts: deps.queryContacts,
            idleMonitor: deps.idleMonitor,
            appLockManager: deps.appLockManager,
            modelManager: deps.aiModelManager,
            aiEngineResolver: deps.aiEngineResolver,
            aiProcessingQueue: deps.aiProcessingQueue,
            summarizeThread: deps.summarizeThread,
            smartReply: deps.smartReply,
            searchUseCase: deps.searchUseCase
        )
        .environment(deps.settingsStore)
        .modelContainer(deps.modelContainer)
        .task {
            await deps.searchIndexManager.openIndex()
            await deps.searchIndexManager.reindexIfNeeded()
        }
        #endif
    }
}

// MARK: - Dependency Container

/// Encapsulates all app-level dependencies that require a valid ModelContainer.
/// Created once at launch and passed through the view hierarchy.
@MainActor
private struct AppDependencies {
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

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer

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
}
