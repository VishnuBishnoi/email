import Testing
import Foundation
import SwiftData
@testable import VaultMailFeature

// MARK: - Mock Embedding Engine

/// Lightweight configurable mock for testing SearchIndexManager embedding generation.
private struct StubEmbeddingEngine: AIEngineProtocol {
    var available: Bool = true
    var embedResult: [Float]? = nil
    var shouldThrow: Bool = false

    func isAvailable() async -> Bool { available }

    func generate(prompt: String, maxTokens: Int) async -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }

    func classify(text: String, categories: [String]) async throws -> String { "" }

    func embed(text: String) async throws -> [Float] {
        if shouldThrow {
            throw NSError(domain: "StubEmbeddingEngine", code: 1, userInfo: nil)
        }
        return embedResult ?? []
    }

    func unload() async {}
}

// MARK: - Tests

@Suite("SearchIndexManager Tests")
struct SearchIndexManagerTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.createForTesting()
    }

    private func makeTempFTS5Dir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    @MainActor
    private func makeEmail(
        id: String = "email-1",
        accountId: String = "acc-1",
        subject: String = "Test Subject",
        bodyPlain: String? = "Test body content",
        fromAddress: String = "test@example.com",
        fromName: String? = "Test User",
        in container: ModelContainer
    ) -> Email {
        let email = Email(
            id: id,
            accountId: accountId,
            threadId: "thread-\(id)",
            messageId: "msg-\(id)",
            fromAddress: fromAddress,
            fromName: fromName,
            subject: subject,
            bodyPlain: bodyPlain
        )
        container.mainContext.insert(email)
        try? container.mainContext.save()
        return email
    }

    @MainActor
    private func fetchSearchIndices(in container: ModelContainer) throws -> [SearchIndex] {
        let descriptor = FetchDescriptor<SearchIndex>()
        return try container.mainContext.fetch(descriptor)
    }

    @MainActor
    private func fetchSearchIndex(emailId: String, in container: ModelContainer) throws -> SearchIndex? {
        let predicate = #Predicate<SearchIndex> { $0.emailId == emailId }
        var descriptor = FetchDescriptor<SearchIndex>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try container.mainContext.fetch(descriptor).first
    }

    // MARK: - indexEmail

    @Test("indexEmail inserts into FTS5 and creates SearchIndex entry")
    @MainActor
    func indexEmailCreatesEntries() async throws {
        let container = try makeContainer()
        let tempDir = try makeTempFTS5Dir()
        let fts5 = FTS5Manager(databaseDirectoryURL: tempDir)
        let manager = SearchIndexManager(fts5Manager: fts5, modelContainer: container)

        await manager.openIndex()

        let engine = StubEmbeddingEngine(available: true, embedResult: [0.6, 0.8])
        let email = makeEmail(in: container)

        await manager.indexEmail(email, engine: engine)

        // Verify SearchIndex entry was created
        let indices = try fetchSearchIndices(in: container)
        #expect(indices.count == 1)
        #expect(indices[0].emailId == "email-1")
        #expect(indices[0].accountId == "acc-1")
        #expect(indices[0].content.contains("Test Subject"))
        #expect(indices[0].content.contains("test@example.com"))
        #expect(indices[0].embedding != nil)

        // Verify FTS5 entry was created
        let ftsResults = try await fts5.search(query: "Test Subject")
        #expect(ftsResults.count == 1)
        #expect(ftsResults[0].emailId == "email-1")

        await manager.closeIndex()
    }

    @Test("indexEmail with nil engine creates SearchIndex with nil embedding")
    @MainActor
    func indexEmailNilEngine() async throws {
        let container = try makeContainer()
        let tempDir = try makeTempFTS5Dir()
        let fts5 = FTS5Manager(databaseDirectoryURL: tempDir)
        let manager = SearchIndexManager(fts5Manager: fts5, modelContainer: container)

        await manager.openIndex()

        let email = makeEmail(in: container)

        await manager.indexEmail(email, engine: nil)

        // Verify SearchIndex entry was created with nil embedding
        let entry = try #require(try fetchSearchIndex(emailId: "email-1", in: container))
        #expect(entry.emailId == "email-1")
        #expect(entry.accountId == "acc-1")
        #expect(entry.embedding == nil)

        // FTS5 should still have the entry
        let ftsResults = try await fts5.search(query: "Test Subject")
        #expect(ftsResults.count == 1)

        await manager.closeIndex()
    }

    @Test("indexEmail upserts existing entry instead of duplicating")
    @MainActor
    func indexEmailUpserts() async throws {
        let container = try makeContainer()
        let tempDir = try makeTempFTS5Dir()
        let fts5 = FTS5Manager(databaseDirectoryURL: tempDir)
        let manager = SearchIndexManager(fts5Manager: fts5, modelContainer: container)

        await manager.openIndex()

        let email = makeEmail(
            id: "email-upsert",
            subject: "Original Subject",
            bodyPlain: "Original body",
            in: container
        )

        // Index first time
        await manager.indexEmail(email, engine: nil)

        let indicesAfterFirst = try fetchSearchIndices(in: container)
        #expect(indicesAfterFirst.count == 1)

        // Update email content and re-index
        email.subject = "Updated Subject"
        email.bodyPlain = "Updated body"
        try? container.mainContext.save()

        await manager.indexEmail(email, engine: nil)

        // Should still be 1 entry, not 2
        let indicesAfterSecond = try fetchSearchIndices(in: container)
        #expect(indicesAfterSecond.count == 1)
        #expect(indicesAfterSecond[0].content.contains("Updated Subject"))

        await manager.closeIndex()
    }

    // MARK: - removeEmail

    @Test("removeEmail removes from both FTS5 and SearchIndex")
    @MainActor
    func removeEmailRemovesBoth() async throws {
        let container = try makeContainer()
        let tempDir = try makeTempFTS5Dir()
        let fts5 = FTS5Manager(databaseDirectoryURL: tempDir)
        let manager = SearchIndexManager(fts5Manager: fts5, modelContainer: container)

        await manager.openIndex()

        let email = makeEmail(in: container)
        await manager.indexEmail(email, engine: nil)

        // Verify entry exists
        #expect(try fetchSearchIndices(in: container).count == 1)

        // Remove it
        await manager.removeEmail(emailId: "email-1")

        // Verify SearchIndex is empty
        let indices = try fetchSearchIndices(in: container)
        #expect(indices.isEmpty)

        // Verify FTS5 is empty
        let ftsResults = try await fts5.search(query: "Test Subject")
        #expect(ftsResults.isEmpty)

        await manager.closeIndex()
    }

    @Test("removeEmail on non-existent ID is a no-op")
    @MainActor
    func removeEmailNonExistent() async throws {
        let container = try makeContainer()
        let tempDir = try makeTempFTS5Dir()
        let fts5 = FTS5Manager(databaseDirectoryURL: tempDir)
        let manager = SearchIndexManager(fts5Manager: fts5, modelContainer: container)

        await manager.openIndex()

        // Should not crash or throw
        await manager.removeEmail(emailId: "does-not-exist")

        // Verify nothing was affected
        let indices = try fetchSearchIndices(in: container)
        #expect(indices.isEmpty)

        await manager.closeIndex()
    }

    // MARK: - removeAllForAccount

    @Test("removeAllForAccount removes all entries for that account")
    @MainActor
    func removeAllForAccount() async throws {
        let container = try makeContainer()
        let tempDir = try makeTempFTS5Dir()
        let fts5 = FTS5Manager(databaseDirectoryURL: tempDir)
        let manager = SearchIndexManager(fts5Manager: fts5, modelContainer: container)

        await manager.openIndex()

        // Index emails from two accounts
        let email1 = makeEmail(id: "e1", accountId: "acc-1", subject: "Email One", in: container)
        let email2 = makeEmail(id: "e2", accountId: "acc-1", subject: "Email Two", in: container)
        let email3 = makeEmail(id: "e3", accountId: "acc-2", subject: "Email Three", in: container)

        await manager.indexEmail(email1, engine: nil)
        await manager.indexEmail(email2, engine: nil)
        await manager.indexEmail(email3, engine: nil)

        #expect(try fetchSearchIndices(in: container).count == 3)

        // Remove all for acc-1
        await manager.removeAllForAccount(accountId: "acc-1")

        // Only acc-2's entry should remain
        let remaining = try fetchSearchIndices(in: container)
        #expect(remaining.count == 1)
        #expect(remaining[0].accountId == "acc-2")
        #expect(remaining[0].emailId == "e3")

        // FTS5 should only have acc-2's entry
        let ftsResultsAcc1 = try await fts5.search(query: "Email One")
        #expect(ftsResultsAcc1.isEmpty)

        let ftsResultsAcc2 = try await fts5.search(query: "Email Three")
        #expect(ftsResultsAcc2.count == 1)

        await manager.closeIndex()
    }

    // MARK: - backfillAccountIds

    @Test("backfillAccountIds fills empty accountId from Email")
    @MainActor
    func backfillAccountIds() async throws {
        let container = try makeContainer()
        let tempDir = try makeTempFTS5Dir()
        let fts5 = FTS5Manager(databaseDirectoryURL: tempDir)
        let manager = SearchIndexManager(fts5Manager: fts5, modelContainer: container)

        // Create emails in SwiftData
        _ = makeEmail(id: "bf-1", accountId: "acc-A", subject: "Backfill One", in: container)
        _ = makeEmail(id: "bf-2", accountId: "acc-B", subject: "Backfill Two", in: container)

        // Manually insert SearchIndex entries with empty accountId
        // (simulating pre-migration state)
        let context = container.mainContext
        let si1 = SearchIndex(emailId: "bf-1", accountId: "", content: "Backfill One")
        let si2 = SearchIndex(emailId: "bf-2", accountId: "", content: "Backfill Two")
        context.insert(si1)
        context.insert(si2)
        try context.save()

        // Run backfill
        await manager.backfillAccountIds()

        // Verify accountIds are now filled
        let entry1 = try #require(try fetchSearchIndex(emailId: "bf-1", in: container))
        #expect(entry1.accountId == "acc-A")

        let entry2 = try #require(try fetchSearchIndex(emailId: "bf-2", in: container))
        #expect(entry2.accountId == "acc-B")
    }

    // MARK: - Lifecycle

    @Test("openIndex and closeIndex lifecycle works without error")
    @MainActor
    func openCloseLifecycle() async throws {
        let container = try makeContainer()
        let tempDir = try makeTempFTS5Dir()
        let fts5 = FTS5Manager(databaseDirectoryURL: tempDir)
        let manager = SearchIndexManager(fts5Manager: fts5, modelContainer: container)

        // Open
        await manager.openIndex()
        let isOpen = await fts5.isOpen
        #expect(isOpen)

        // Index something to verify it works after open
        let email = makeEmail(in: container)
        await manager.indexEmail(email, engine: nil)

        let indices = try fetchSearchIndices(in: container)
        #expect(indices.count == 1)

        // Close
        await manager.closeIndex()
        let isOpenAfterClose = await fts5.isOpen
        #expect(!isOpenAfterClose)
    }
}
