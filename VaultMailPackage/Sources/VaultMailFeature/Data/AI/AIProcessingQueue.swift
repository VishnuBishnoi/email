import Foundation
import SwiftData

/// Background batch processing queue for AI classification after sync.
///
/// Runs categorization and spam detection on newly synced emails.
/// Respects concurrency constraints:
/// - LLM tasks (generative): serial — prevents concurrent model loads
/// - CoreML tasks (classification): may run concurrently — lightweight, ANE-backed
///
/// Batch size: 50 emails with yields between batches for responsive UI.
///
/// Spec ref: FR-AI-07, AC-A-04b, AC-A-09
@MainActor
@Observable
public final class AIProcessingQueue: Sendable {

    // MARK: - State

    /// Whether the queue is currently processing.
    public private(set) var isProcessing = false

    /// Number of emails processed in the current batch.
    public private(set) var processedCount = 0

    /// Total number of emails queued for processing.
    public private(set) var totalCount = 0

    /// Number of emails categorized in the last run.
    public private(set) var lastCategorizedCount = 0

    /// Number of emails flagged as spam in the last run.
    public private(set) var lastSpamCount = 0

    // MARK: - Dependencies

    private let categorize: CategorizeEmailUseCaseProtocol
    private let detectSpam: DetectSpamUseCaseProtocol
    private let aiRepository: AIRepositoryProtocol?
    private let modelContainer: ModelContainer?
    private let searchIndexManager: SearchIndexManager?
    private let aiEngineResolver: AIEngineResolver?

    /// Batch size for processing. 50 emails per batch with yields between.
    private let batchSize = 50

    /// Active processing task (for cancellation).
    private var processingTask: Task<Void, Never>?

    /// Generation counter to detect stale task continuations after re-enqueue (P1-6).
    private var generation: Int = 0

    // MARK: - Init

    public init(
        categorize: CategorizeEmailUseCaseProtocol,
        detectSpam: DetectSpamUseCaseProtocol,
        aiRepository: AIRepositoryProtocol? = nil,
        modelContainer: ModelContainer? = nil,
        searchIndexManager: SearchIndexManager? = nil,
        aiEngineResolver: AIEngineResolver? = nil
    ) {
        self.categorize = categorize
        self.detectSpam = detectSpam
        self.aiRepository = aiRepository
        self.modelContainer = modelContainer
        self.searchIndexManager = searchIndexManager
        self.aiEngineResolver = aiEngineResolver
    }

    // MARK: - Public API

    /// Enqueue emails for background AI processing.
    ///
    /// Called after `SyncEmailsUseCase` completes a sync batch.
    /// Processes categorization and spam detection in batches of 50.
    ///
    /// - Parameter emails: Newly synced emails to process.
    public func enqueue(emails: [Email]) {
        // Filter to only uncategorized emails (don't re-process)
        let uncategorized = emails.filter { email in
            email.aiCategory == AICategory.uncategorized.rawValue || email.aiCategory == nil
        }

        guard !uncategorized.isEmpty else { return }

        // Cancel any existing processing before resetting state (P1-6)
        processingTask?.cancel()
        processingTask = nil

        // Increment generation to invalidate stale task continuations
        generation += 1
        let currentGeneration = generation

        totalCount = uncategorized.count
        processedCount = 0
        lastCategorizedCount = 0
        lastSpamCount = 0
        isProcessing = true

        processingTask = Task { [weak self] in
            guard let self else { return }
            await self.processBatches(uncategorized, generation: currentGeneration)
        }
    }

    /// Cancel any active processing.
    public func cancel() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
    }

    // MARK: - Processing

    private func processBatches(_ emails: [Email], generation: Int) async {
        var categorizedTotal = 0
        var spamTotal = 0

        // Process in batches
        let batches = stride(from: 0, to: emails.count, by: batchSize).map { startIndex in
            let endIndex = min(startIndex + batchSize, emails.count)
            return Array(emails[startIndex..<endIndex])
        }

        for batch in batches {
            // Check both cancellation and generation to prevent stale writes (P1-6)
            guard !Task.isCancelled, self.generation == generation else { break }

            // Categorize batch
            let categorized = await categorize.categorizeBatch(emails: batch)
            categorizedTotal += categorized

            // Spam detection batch
            let spamDetected = await detectSpam.detectBatch(emails: batch)
            spamTotal += spamDetected

            // Semantic embedding generation (FR-AI-05 / AC-A-07)
            // Generates embeddings and indexes emails for semantic search.
            // Uses SearchIndex SwiftData model for persistence.
            if let repo = aiRepository {
                await generateEmbeddings(for: batch, using: repo, generation: generation)
            }

            // Only update state if this generation is still current
            guard self.generation == generation else { break }
            processedCount += batch.count
            lastCategorizedCount = categorizedTotal
            lastSpamCount = spamTotal

            // Yield between batches for UI responsiveness
            await Task.yield()
        }

        // Only mark done if this generation is still current
        if self.generation == generation {
            isProcessing = false
        }
    }

    // MARK: - Embedding Generation & Indexing (FR-AI-05, FR-SEARCH-08)

    /// Generate embeddings and index emails for search.
    ///
    /// Delegates to SearchIndexManager (single owner of search index mutations)
    /// when available. Falls back to direct SearchIndex manipulation for
    /// backward compatibility.
    ///
    /// Spec ref: FR-AI-05, FR-SEARCH-08
    private func generateEmbeddings(
        for emails: [Email],
        using repo: AIRepositoryProtocol,
        generation: Int
    ) async {
        // Delegate to SearchIndexManager when available (FR-SEARCH-08: single owner)
        if let indexManager = searchIndexManager {
            // Resolve embedding engine (P0 fix: was passing nil, disabling semantic indexing)
            let engine: (any AIEngineProtocol)?
            if let resolver = aiEngineResolver {
                engine = await resolver.resolveGenerativeEngine()
            } else {
                engine = nil
            }
            for email in emails {
                guard !Task.isCancelled, self.generation == generation else { break }
                await indexManager.indexEmail(email, engine: engine)
            }
            return
        }

        // Legacy fallback: direct SearchIndex manipulation
        guard let container = modelContainer else { return }
        let context = ModelContext(container)

        for email in emails {
            guard !Task.isCancelled, self.generation == generation else { break }
            let searchText = [email.subject, email.fromAddress,
                              email.bodyPlain ?? email.snippet ?? ""]
                .joined(separator: " ")

            let embedding = try? await repo.generateEmbedding(text: searchText)

            let emailId = email.id
            let descriptor = FetchDescriptor<SearchIndex>(
                predicate: #Predicate { $0.emailId == emailId }
            )

            if let existing = try? context.fetch(descriptor).first {
                existing.content = searchText
                existing.embedding = (embedding?.isEmpty == false) ? embedding : existing.embedding
            } else {
                let entry = SearchIndex(
                    emailId: email.id,
                    content: searchText,
                    embedding: (embedding?.isEmpty == false) ? embedding : nil
                )
                context.insert(entry)
            }
        }

        try? context.save()
    }
}
