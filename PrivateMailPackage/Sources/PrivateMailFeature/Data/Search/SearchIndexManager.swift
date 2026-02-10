import Foundation
import SwiftData

/// Single owner of all search index mutations (FTS5 + SwiftData SearchIndex).
///
/// Orchestrates both FTS5 inserts/deletes and SearchIndex entity management,
/// ensuring the two stores stay in sync. All operations are fault-tolerant —
/// indexing failures are non-fatal and never crash the app.
///
/// This class is `@MainActor` because it accesses SwiftData's `ModelContext`
/// (which requires main-actor isolation). It accesses `FTS5Manager` (a plain
/// actor) via `await`.
///
/// Spec ref: FR-SEARCH-08, AC-S-09
@MainActor
public final class SearchIndexManager {

    // MARK: - Dependencies

    private let fts5Manager: FTS5Manager
    private let modelContainer: ModelContainer

    // MARK: - Init

    /// Creates a SearchIndexManager that coordinates FTS5 and SwiftData indices.
    ///
    /// - Parameters:
    ///   - fts5Manager: The FTS5 full-text search manager (plain actor).
    ///   - modelContainer: The SwiftData model container for SearchIndex entities.
    public init(fts5Manager: FTS5Manager, modelContainer: ModelContainer) {
        self.fts5Manager = fts5Manager
        self.modelContainer = modelContainer
    }

    // MARK: - Indexing

    /// Indexes a single email into both FTS5 and SwiftData.
    ///
    /// Builds search text from the email's subject, sender, and body, inserts
    /// into FTS5 for keyword search, generates an embedding if an AI engine
    /// is available, and upserts a SearchIndex entry in SwiftData.
    ///
    /// All operations use `try?` — indexing failures are non-fatal.
    ///
    /// - Parameters:
    ///   - email: The email to index.
    ///   - engine: Optional AI engine for embedding generation. When nil,
    ///     the SearchIndex entry is created with a nil embedding.
    ///
    /// Spec ref: FR-SEARCH-08, AC-S-09
    public func indexEmail(_ email: Email, engine: (any AIEngineProtocol)?) async {
        let emailId = email.id
        let accountId = email.accountId
        let subject = email.subject
        let bodyPlain = email.bodyPlain ?? ""
        let fromName = email.fromName ?? ""
        let fromAddress = email.fromAddress
        let snippet = email.snippet ?? ""

        // Build search text for embedding
        let searchText = [subject, fromAddress, email.bodyPlain ?? snippet].joined(separator: " ")

        // Insert into FTS5 (non-fatal on failure)
        try? await fts5Manager.insert(
            emailId: emailId,
            accountId: accountId,
            subject: subject,
            body: bodyPlain,
            senderName: fromName,
            senderEmail: fromAddress
        )

        // Generate embedding if engine is available
        var embeddingData: Data?
        if let engine {
            if let vector = await GenerateEmbeddingUseCase.embedQuery(text: searchText, using: engine) {
                embeddingData = vector.withUnsafeBufferPointer { buffer in
                    Data(buffer: buffer)
                }
            }
        }

        // Upsert SearchIndex entry in SwiftData
        let context = modelContainer.mainContext
        let predicate = #Predicate<SearchIndex> { $0.emailId == emailId }
        var descriptor = FetchDescriptor<SearchIndex>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            // Update existing entry
            existing.content = searchText
            existing.embedding = embeddingData
            existing.accountId = accountId
        } else {
            // Insert new entry
            let entry = SearchIndex(
                emailId: emailId,
                accountId: accountId,
                content: searchText,
                embedding: embeddingData
            )
            context.insert(entry)
        }

        try? context.save()
    }

    // MARK: - Removal

    /// Removes an email from both FTS5 and SwiftData search indices.
    ///
    /// No-op if the email ID does not exist in either store.
    ///
    /// - Parameter emailId: Identifier of the email to remove.
    ///
    /// Spec ref: FR-SEARCH-08
    public func removeEmail(emailId: String) async {
        try? await fts5Manager.delete(emailId: emailId)

        let context = modelContainer.mainContext
        let predicate = #Predicate<SearchIndex> { $0.emailId == emailId }
        var descriptor = FetchDescriptor<SearchIndex>(predicate: predicate)
        descriptor.fetchLimit = 1

        if let entry = try? context.fetch(descriptor).first {
            context.delete(entry)
            try? context.save()
        }
    }

    /// Removes all search index entries for a given account from both
    /// FTS5 and SwiftData.
    ///
    /// - Parameter accountId: Account whose entries should be removed.
    ///
    /// Spec ref: FR-SEARCH-08
    public func removeAllForAccount(accountId: String) async {
        try? await fts5Manager.deleteAll(accountId: accountId)

        let context = modelContainer.mainContext
        let predicate = #Predicate<SearchIndex> { $0.accountId == accountId }
        let descriptor = FetchDescriptor<SearchIndex>(predicate: predicate)

        if let entries = try? context.fetch(descriptor) {
            for entry in entries {
                context.delete(entry)
            }
            try? context.save()
        }
    }

    // MARK: - Migration

    /// Backfills empty `accountId` fields on existing SearchIndex entries.
    ///
    /// Looks up each entry's corresponding Email to retrieve the accountId.
    /// Batch-saves every 100 entries for efficiency. This operation is
    /// idempotent — entries that already have an accountId are skipped
    /// by the predicate.
    ///
    /// Spec ref: FR-SEARCH-08
    public func backfillAccountIds() async {
        let context = modelContainer.mainContext
        let emptyAccountId = ""
        let predicate = #Predicate<SearchIndex> { $0.accountId == emptyAccountId }
        let descriptor = FetchDescriptor<SearchIndex>(predicate: predicate)

        guard let entries = try? context.fetch(descriptor), !entries.isEmpty else {
            return
        }

        var updateCount = 0

        for entry in entries {
            let entryEmailId = entry.emailId
            let emailPredicate = #Predicate<Email> { $0.id == entryEmailId }
            var emailDescriptor = FetchDescriptor<Email>(predicate: emailPredicate)
            emailDescriptor.fetchLimit = 1

            if let email = try? context.fetch(emailDescriptor).first {
                entry.accountId = email.accountId
                updateCount += 1

                // Batch save every 100 entries
                if updateCount % 100 == 0 {
                    try? context.save()
                }
            }
        }

        // Final save for remaining entries
        if updateCount % 100 != 0 {
            try? context.save()
        }
    }

    // MARK: - Reindex

    /// Indexes all emails that are not yet in the FTS5 index.
    ///
    /// Fetches all Email entities from SwiftData and inserts any that are
    /// missing from FTS5. This is used on first launch after the search
    /// feature is added to backfill the index with existing emails.
    ///
    /// Uses a UserDefaults guard to run only once.
    ///
    /// Spec ref: FR-SEARCH-08, AC-S-09
    public func reindexIfNeeded() async {
        let key = "searchFTS5InitialIndexComplete"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<Email>()
        guard let emails = try? context.fetch(descriptor), !emails.isEmpty else {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        for email in emails {
            try? await fts5Manager.insert(
                emailId: email.id,
                accountId: email.accountId,
                subject: email.subject,
                body: email.bodyPlain ?? "",
                senderName: email.fromName ?? "",
                senderEmail: email.fromAddress
            )
            // Yield periodically to keep UI responsive
            if email.id.hashValue % 50 == 0 {
                await Task.yield()
            }
        }

        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - Lifecycle

    /// Opens the FTS5 search database.
    ///
    /// Should be called during app startup before any indexing or search
    /// operations. Failures are silently ignored — the app can still
    /// function with SwiftData-only search.
    public func openIndex() async {
        try? await fts5Manager.open()
    }

    /// Closes the FTS5 search database, releasing resources.
    ///
    /// Should be called during app shutdown or when search is no longer needed.
    public func closeIndex() async {
        await fts5Manager.close()
    }
}
