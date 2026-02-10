import Foundation
import SwiftData

/// Orchestrates hybrid email search combining FTS5 keyword search
/// with semantic embedding search via Reciprocal Rank Fusion (RRF).
///
/// This is the main entry point for search, called from the UI layer.
/// It runs on `@MainActor` because it accesses SwiftData's `mainContext`
/// for filter application and Email model hydration.
///
/// Search flow:
/// 1. Parse query text and filters
/// 2. Run FTS5 keyword search and semantic vector search in parallel
/// 3. Merge results using RRF
/// 4. Hydrate Email models from SwiftData
/// 5. Apply structured filters (sender, date, attachment, category, read status)
/// 6. Apply scope filtering (all mail vs. current folder)
/// 7. Build SearchResult value types for the view layer
///
/// Spec ref: FR-SEARCH-05, FR-SEARCH-06, FR-SEARCH-07
@MainActor
public final class SearchEmailsUseCase {

    // MARK: - Dependencies

    private let fts5Manager: FTS5Manager
    private let vectorEngine: VectorSearchEngine
    private let modelContainer: ModelContainer

    // MARK: - Init

    /// Creates a SearchEmailsUseCase.
    ///
    /// - Parameters:
    ///   - fts5Manager: FTS5 full-text search engine.
    ///   - vectorEngine: In-memory vector similarity search engine.
    ///   - modelContainer: SwiftData model container for Email hydration.
    public init(
        fts5Manager: FTS5Manager,
        vectorEngine: VectorSearchEngine,
        modelContainer: ModelContainer
    ) {
        self.fts5Manager = fts5Manager
        self.vectorEngine = vectorEngine
        self.modelContainer = modelContainer
    }

    // MARK: - Public API

    /// Execute a hybrid search query.
    ///
    /// - Parameters:
    ///   - query: Parsed search query with text and structured filters.
    ///   - engine: AI engine for query embedding generation. Pass nil for
    ///     keyword-only search (graceful degradation per AC-S-08).
    /// - Returns: Array of `SearchResult` sorted by relevance score descending.
    public func execute(
        query: SearchQuery,
        engine: (any AIEngineProtocol)?
    ) async -> [SearchResult] {
        let hasText = !query.text.isEmpty
        let hasFilters = query.filters.hasActiveFilters

        // Nothing to search for
        guard hasText || hasFilters else { return [] }

        // Step 1: Run keyword + semantic search in parallel (if text query present)
        var mergedResults: [RRFMerger.MergedResult] = []

        if hasText {
            // Run FTS5 and semantic search concurrently
            async let keywordTask = performKeywordSearch(query: query.text)
            async let semanticTask = performSemanticSearch(query: query.text, engine: engine)

            let keywordResults = await keywordTask
            let semanticResults = await semanticTask

            // Convert to RankedItem arrays
            let keywordRanked = keywordResults.enumerated().map { index, result in
                RRFMerger.RankedItem(emailId: result.emailId, rank: index + 1)
            }
            let semanticRanked = semanticResults.enumerated().map { index, result in
                RRFMerger.RankedItem(emailId: result.emailId, rank: index + 1)
            }

            // Merge via RRF
            mergedResults = RRFMerger.merge(
                keywordResults: keywordRanked,
                semanticResults: semanticRanked
            )
        }

        // Step 2: Hydrate Email models from SwiftData
        let context = modelContainer.mainContext
        var emailsWithScores: [(email: Email, score: Double, matchSource: MatchSource)]

        if hasText && !mergedResults.isEmpty {
            // Fetch emails by merged result IDs
            emailsWithScores = fetchEmails(
                for: mergedResults,
                context: context
            )
        } else if !hasText && hasFilters {
            // Filter-only mode: fetch all emails from SwiftData
            let allEmails = fetchAllEmails(context: context)
            emailsWithScores = allEmails.map { (email: $0, score: 0.0, matchSource: .keyword) }
        } else {
            // Text search returned no results
            emailsWithScores = []
        }

        // Step 3: Apply structured filters
        let filtered = applyFilters(
            emails: emailsWithScores,
            filters: query.filters,
            scope: query.scope
        )

        // Step 4: Build SearchResult value types
        var results: [SearchResult] = []
        for item in filtered {
            let result = await buildSearchResult(
                email: item.email,
                score: item.score,
                matchSource: item.matchSource,
                queryText: query.text
            )
            results.append(result)
        }

        // Step 5: Sort by score descending
        results.sort { $0.score > $1.score }

        return results
    }

    // MARK: - Private: Search Execution

    /// Performs FTS5 keyword search. Returns empty array on failure.
    private func performKeywordSearch(query: String) async -> [FTS5SearchResult] {
        do {
            return try await fts5Manager.search(query: query)
        } catch {
            return []
        }
    }

    /// Performs semantic vector search. Returns empty array if engine is nil
    /// or embedding generation fails.
    ///
    /// Lazily loads vectors from SwiftData SearchIndex into the in-memory
    /// VectorSearchEngine on each query to pick up newly indexed embeddings.
    private func performSemanticSearch(
        query: String,
        engine: (any AIEngineProtocol)?
    ) async -> [VectorSearchResult] {
        guard let engine else { return [] }

        guard let embedding = await GenerateEmbeddingUseCase.embedQuery(
            text: query,
            using: engine
        ) else {
            return []
        }

        // Load vectors from SwiftData into the in-memory engine (P0 fix)
        await loadVectorsFromStore()

        return await vectorEngine.search(query: embedding)
    }

    /// Loads embedding vectors from SwiftData SearchIndex entries into the
    /// in-memory VectorSearchEngine. Only loads entries that have non-nil
    /// embedding data. Called before each semantic search to ensure the
    /// engine has current data.
    private func loadVectorsFromStore() async {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<SearchIndex>()
        guard let entries = try? context.fetch(descriptor) else { return }

        var vectorEntries: [VectorEntry] = []
        vectorEntries.reserveCapacity(entries.count)

        for entry in entries {
            guard let data = entry.embedding, !data.isEmpty else { continue }
            let floats = data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }
            guard !floats.isEmpty else { continue }
            vectorEntries.append(VectorEntry(emailId: entry.emailId, embedding: floats))
        }

        await vectorEngine.loadVectors(from: vectorEntries)
    }

    // MARK: - Private: SwiftData Hydration

    /// Fetches Email models for merged search results, preserving score/source info.
    private func fetchEmails(
        for mergedResults: [RRFMerger.MergedResult],
        context: ModelContext
    ) -> [(email: Email, score: Double, matchSource: MatchSource)] {
        let emailIds = mergedResults.map(\.emailId)
        let scoreMap = Dictionary(
            uniqueKeysWithValues: mergedResults.map { ($0.emailId, ($0.score, $0.matchSource)) }
        )

        let predicate = #Predicate<Email> { email in
            emailIds.contains(email.id)
        }

        var descriptor = FetchDescriptor<Email>(predicate: predicate)
        descriptor.fetchLimit = emailIds.count

        guard let emails = try? context.fetch(descriptor) else { return [] }

        return emails.compactMap { email in
            guard let (score, matchSource) = scoreMap[email.id] else { return nil }
            return (email: email, score: score, matchSource: matchSource)
        }
    }

    /// Fetches all emails from SwiftData (for filter-only searches).
    private func fetchAllEmails(context: ModelContext) -> [Email] {
        let descriptor = FetchDescriptor<Email>()
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Private: Filter Application

    /// Applies structured filters and scope to the email list.
    private func applyFilters(
        emails: [(email: Email, score: Double, matchSource: MatchSource)],
        filters: SearchFilters,
        scope: SearchScope
    ) -> [(email: Email, score: Double, matchSource: MatchSource)] {
        emails.filter { item in
            let email = item.email

            // Sender filter (case-insensitive)
            if let sender = filters.sender {
                let senderLower = sender.lowercased()
                let matchesAddress = email.fromAddress.lowercased().contains(senderLower)
                let matchesName = email.fromName?.lowercased().contains(senderLower) ?? false
                guard matchesAddress || matchesName else { return false }
            }

            // Date range filter
            if let dateRange = filters.dateRange {
                guard let received = email.dateReceived,
                      received >= dateRange.start && received <= dateRange.end else {
                    return false
                }
            }

            // Attachment filter
            if let hasAttachment = filters.hasAttachment, hasAttachment {
                guard !email.attachments.isEmpty else { return false }
            }

            // Category filter
            if let category = filters.category {
                guard email.aiCategory == category.rawValue else { return false }
            }

            // Read status filter
            if let isRead = filters.isRead {
                guard email.isRead == isRead else { return false }
            }

            // Folder filter (P1 fix: was defined in model but never applied)
            if let folderName = filters.folder {
                let folderLower = folderName.lowercased()
                let inFolder = email.emailFolders.contains { emailFolder in
                    emailFolder.folder?.name.lowercased() == folderLower
                }
                guard inFolder else { return false }
            }

            // Scope filter
            switch scope {
            case .allMail:
                break
            case .currentFolder(let folderId):
                let inFolder = email.emailFolders.contains { emailFolder in
                    emailFolder.folder?.id == folderId
                }
                guard inFolder else { return false }
            }

            return true
        }
    }

    // MARK: - Private: Result Building

    /// Builds a SearchResult value type from an Email model.
    private func buildSearchResult(
        email: Email,
        score: Double,
        matchSource: MatchSource,
        queryText: String
    ) async -> SearchResult {
        // Try to get highlighted subject from FTS5
        var displaySubject = email.subject
        if !queryText.isEmpty {
            if let highlighted = try? await fts5Manager.highlight(
                emailId: email.id,
                column: .subject,
                query: queryText
            ) {
                displaySubject = highlighted
            }
        }

        // Build snippet from body or existing snippet
        let snippet: String
        if let bodyPlain = email.bodyPlain {
            snippet = String(bodyPlain.prefix(200))
        } else if let emailSnippet = email.snippet {
            snippet = emailSnippet
        } else {
            snippet = ""
        }

        return SearchResult(
            id: email.id,
            threadId: email.threadId,
            emailId: email.id,
            subject: displaySubject,
            senderName: email.fromName ?? email.fromAddress,
            senderEmail: email.fromAddress,
            date: email.dateReceived ?? Date.distantPast,
            snippet: snippet,
            highlightRanges: [],
            hasAttachment: !email.attachments.isEmpty,
            score: score,
            matchSource: matchSource,
            accountId: email.accountId,
            isRead: email.isRead
        )
    }
}
