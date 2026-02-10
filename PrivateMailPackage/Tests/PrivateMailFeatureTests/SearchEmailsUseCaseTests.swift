import Testing
import Foundation
import SwiftData
@testable import PrivateMailFeature

// MARK: - Mock Search Engine

/// Configurable mock AI engine for search tests.
private struct MockSearchEngine: AIEngineProtocol {
    var available: Bool = false
    var embedResult: [Float] = []
    var shouldThrow: Bool = false

    func isAvailable() async -> Bool { available }

    func generate(prompt: String, maxTokens: Int) async -> AsyncStream<String> {
        AsyncStream { $0.finish() }
    }

    func classify(text: String, categories: [String]) async throws -> String { "" }

    func embed(text: String) async throws -> [Float] {
        if shouldThrow {
            throw NSError(domain: "MockSearchEngine", code: 1, userInfo: nil)
        }
        return embedResult
    }

    func unload() async {}
}

// MARK: - Tests

@Suite("SearchEmailsUseCase Tests")
@MainActor
struct SearchEmailsUseCaseTests {

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

    private func makeSUT(
        container: ModelContainer,
        fts5Dir: URL
    ) async throws -> (SearchEmailsUseCase, FTS5Manager, VectorSearchEngine) {
        let fts5Manager = FTS5Manager(databaseDirectoryURL: fts5Dir)
        try await fts5Manager.open()

        let vectorEngine = VectorSearchEngine()

        let useCase = SearchEmailsUseCase(
            fts5Manager: fts5Manager,
            vectorEngine: vectorEngine,
            modelContainer: container
        )

        return (useCase, fts5Manager, vectorEngine)
    }

    /// Inserts an email into SwiftData and the FTS5 index.
    @discardableResult
    private func insertEmail(
        id: String,
        accountId: String = "acc-1",
        threadId: String? = nil,
        subject: String = "Test Subject",
        bodyPlain: String? = "Test body content",
        fromAddress: String = "sender@example.com",
        fromName: String? = "Sender",
        dateReceived: Date? = Date(),
        isRead: Bool = false,
        aiCategory: String? = AICategory.uncategorized.rawValue,
        container: ModelContainer,
        fts5Manager: FTS5Manager
    ) async throws -> Email {
        let resolvedThreadId = threadId ?? "thread-\(id)"
        let email = Email(
            id: id,
            accountId: accountId,
            threadId: resolvedThreadId,
            messageId: "msg-\(id)",
            fromAddress: fromAddress,
            fromName: fromName,
            subject: subject,
            bodyPlain: bodyPlain,
            dateReceived: dateReceived,
            isRead: isRead,
            aiCategory: aiCategory
        )
        container.mainContext.insert(email)
        try container.mainContext.save()

        // Also index in FTS5
        try await fts5Manager.insert(
            emailId: id,
            accountId: accountId,
            subject: subject,
            body: bodyPlain ?? "",
            senderName: fromName ?? "",
            senderEmail: fromAddress
        )

        return email
    }

    /// Creates a Folder and links it to an Email via EmailFolder.
    private func linkEmailToFolder(
        email: Email,
        folderId: String,
        folderName: String = "Inbox",
        container: ModelContainer
    ) throws {
        // Check if folder already exists
        let predicate = #Predicate<Folder> { folder in
            folder.id == folderId
        }
        var descriptor = FetchDescriptor<Folder>(predicate: predicate)
        descriptor.fetchLimit = 1
        let existing = try container.mainContext.fetch(descriptor)

        let folder: Folder
        if let found = existing.first {
            folder = found
        } else {
            folder = Folder(id: folderId, name: folderName, imapPath: folderName)
            container.mainContext.insert(folder)
        }

        let emailFolder = EmailFolder(id: UUID().uuidString)
        emailFolder.email = email
        emailFolder.folder = folder
        container.mainContext.insert(emailFolder)
        try container.mainContext.save()
    }

    /// Creates an Attachment linked to an Email.
    private func addAttachment(
        to email: Email,
        container: ModelContainer
    ) throws {
        let attachment = Attachment(
            id: UUID().uuidString,
            filename: "file.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024
        )
        attachment.email = email
        container.mainContext.insert(attachment)
        try container.mainContext.save()
    }

    // MARK: - Test: Empty query returns empty results

    @Test("Empty query with no filters returns empty results")
    func emptyQueryReturnsEmpty() async throws {
        let container = try makeContainer()
        let fts5Dir = try makeTempFTS5Dir()
        let (useCase, _, _) = try await makeSUT(container: container, fts5Dir: fts5Dir)

        let query = SearchQuery(text: "", filters: SearchFilters())
        let results = await useCase.execute(query: query, engine: nil)

        #expect(results.isEmpty)
    }

    // MARK: - Test: Keyword search returns matching results

    @Test("Keyword search returns matching emails from FTS5")
    func keywordSearchReturnsMatches() async throws {
        let container = try makeContainer()
        let fts5Dir = try makeTempFTS5Dir()
        let (useCase, fts5Manager, _) = try await makeSUT(container: container, fts5Dir: fts5Dir)

        // Insert matching email
        try await insertEmail(
            id: "email-1",
            subject: "Budget Report Q4",
            bodyPlain: "Quarterly budget analysis for Q4",
            container: container,
            fts5Manager: fts5Manager
        )

        // Insert non-matching email
        try await insertEmail(
            id: "email-2",
            subject: "Team Lunch",
            bodyPlain: "Let's grab lunch on Friday",
            container: container,
            fts5Manager: fts5Manager
        )

        let query = SearchQuery(text: "budget")
        let results = await useCase.execute(query: query, engine: nil)

        #expect(results.count == 1)
        #expect(results[0].emailId == "email-1")
        #expect(results[0].matchSource == .keyword)
    }

    // MARK: - Test: Sender filter narrows results

    @Test("Sender filter narrows search results")
    func senderFilterNarrowsResults() async throws {
        let container = try makeContainer()
        let fts5Dir = try makeTempFTS5Dir()
        let (useCase, fts5Manager, _) = try await makeSUT(container: container, fts5Dir: fts5Dir)

        try await insertEmail(
            id: "email-1",
            subject: "Project Update",
            bodyPlain: "Project status update",
            fromAddress: "alice@example.com",
            fromName: "Alice",
            container: container,
            fts5Manager: fts5Manager
        )

        try await insertEmail(
            id: "email-2",
            subject: "Project Review",
            bodyPlain: "Project review notes",
            fromAddress: "bob@example.com",
            fromName: "Bob",
            container: container,
            fts5Manager: fts5Manager
        )

        var filters = SearchFilters()
        filters.sender = "alice"
        let query = SearchQuery(text: "project", filters: filters)
        let results = await useCase.execute(query: query, engine: nil)

        #expect(results.count == 1)
        #expect(results[0].senderEmail == "alice@example.com")
    }

    // MARK: - Test: Date range filter works

    @Test("Date range filter excludes emails outside range")
    func dateRangeFilterWorks() async throws {
        let container = try makeContainer()
        let fts5Dir = try makeTempFTS5Dir()
        let (useCase, fts5Manager, _) = try await makeSUT(container: container, fts5Dir: fts5Dir)

        let now = Date()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: now)!

        try await insertEmail(
            id: "email-recent",
            subject: "Meeting Notes",
            bodyPlain: "Meeting summary",
            dateReceived: twoDaysAgo,
            container: container,
            fts5Manager: fts5Manager
        )

        try await insertEmail(
            id: "email-old",
            subject: "Meeting Agenda",
            bodyPlain: "Old meeting agenda",
            dateReceived: tenDaysAgo,
            container: container,
            fts5Manager: fts5Manager
        )

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        var filters = SearchFilters()
        filters.dateRange = DateRange(start: weekAgo, end: now)
        let query = SearchQuery(text: "meeting", filters: filters)
        let results = await useCase.execute(query: query, engine: nil)

        #expect(results.count == 1)
        #expect(results[0].emailId == "email-recent")
    }

    // MARK: - Test: Attachment filter works

    @Test("Attachment filter returns only emails with attachments")
    func attachmentFilterWorks() async throws {
        let container = try makeContainer()
        let fts5Dir = try makeTempFTS5Dir()
        let (useCase, fts5Manager, _) = try await makeSUT(container: container, fts5Dir: fts5Dir)

        let emailWithAttachment = try await insertEmail(
            id: "email-attach",
            subject: "Invoice Document",
            bodyPlain: "Please find invoice attached",
            container: container,
            fts5Manager: fts5Manager
        )
        try addAttachment(to: emailWithAttachment, container: container)

        try await insertEmail(
            id: "email-no-attach",
            subject: "Invoice Reminder",
            bodyPlain: "Reminder about invoice",
            container: container,
            fts5Manager: fts5Manager
        )

        var filters = SearchFilters()
        filters.hasAttachment = true
        let query = SearchQuery(text: "invoice", filters: filters)
        let results = await useCase.execute(query: query, engine: nil)

        #expect(results.count == 1)
        #expect(results[0].emailId == "email-attach")
        #expect(results[0].hasAttachment == true)
    }

    // MARK: - Test: Category filter works

    @Test("Category filter returns only matching category emails")
    func categoryFilterWorks() async throws {
        let container = try makeContainer()
        let fts5Dir = try makeTempFTS5Dir()
        let (useCase, fts5Manager, _) = try await makeSUT(container: container, fts5Dir: fts5Dir)

        try await insertEmail(
            id: "email-promo",
            subject: "Sale Notification",
            bodyPlain: "Big sale happening now",
            aiCategory: AICategory.promotions.rawValue,
            container: container,
            fts5Manager: fts5Manager
        )

        try await insertEmail(
            id: "email-primary",
            subject: "Sale Details",
            bodyPlain: "Details about the sale",
            aiCategory: AICategory.primary.rawValue,
            container: container,
            fts5Manager: fts5Manager
        )

        var filters = SearchFilters()
        filters.category = .promotions
        let query = SearchQuery(text: "sale", filters: filters)
        let results = await useCase.execute(query: query, engine: nil)

        #expect(results.count == 1)
        #expect(results[0].emailId == "email-promo")
    }

    // MARK: - Test: Scope filtering (currentFolder) works

    @Test("Current folder scope filters to emails in that folder")
    func scopeFilteringCurrentFolder() async throws {
        let container = try makeContainer()
        let fts5Dir = try makeTempFTS5Dir()
        let (useCase, fts5Manager, _) = try await makeSUT(container: container, fts5Dir: fts5Dir)

        let emailInFolder = try await insertEmail(
            id: "email-inbox",
            subject: "Status Report",
            bodyPlain: "Weekly status report",
            container: container,
            fts5Manager: fts5Manager
        )
        try linkEmailToFolder(
            email: emailInFolder,
            folderId: "folder-inbox",
            folderName: "Inbox",
            container: container
        )

        let emailInOther = try await insertEmail(
            id: "email-sent",
            subject: "Status Update",
            bodyPlain: "Status update sent",
            container: container,
            fts5Manager: fts5Manager
        )
        try linkEmailToFolder(
            email: emailInOther,
            folderId: "folder-sent",
            folderName: "Sent",
            container: container
        )

        let query = SearchQuery(
            text: "status",
            scope: .currentFolder(folderId: "folder-inbox")
        )
        let results = await useCase.execute(query: query, engine: nil)

        #expect(results.count == 1)
        #expect(results[0].emailId == "email-inbox")
    }

    // MARK: - Test: Keyword-only fallback when engine unavailable

    @Test("Search falls back to keyword-only when AI engine is unavailable")
    func keywordOnlyFallbackWhenEngineUnavailable() async throws {
        let container = try makeContainer()
        let fts5Dir = try makeTempFTS5Dir()
        let (useCase, fts5Manager, _) = try await makeSUT(container: container, fts5Dir: fts5Dir)

        try await insertEmail(
            id: "email-1",
            subject: "Architecture Design",
            bodyPlain: "System architecture design document",
            container: container,
            fts5Manager: fts5Manager
        )

        let unavailableEngine = MockSearchEngine(available: false)
        let query = SearchQuery(text: "architecture")
        let results = await useCase.execute(query: query, engine: unavailableEngine)

        #expect(results.count == 1)
        #expect(results[0].emailId == "email-1")
        #expect(results[0].matchSource == .keyword)
    }

    // MARK: - Test: Read status filter works

    @Test("Read status filter returns only matching emails")
    func readStatusFilterWorks() async throws {
        let container = try makeContainer()
        let fts5Dir = try makeTempFTS5Dir()
        let (useCase, fts5Manager, _) = try await makeSUT(container: container, fts5Dir: fts5Dir)

        try await insertEmail(
            id: "email-read",
            subject: "Important Notice",
            bodyPlain: "An important notice",
            isRead: true,
            container: container,
            fts5Manager: fts5Manager
        )

        try await insertEmail(
            id: "email-unread",
            subject: "Important Update",
            bodyPlain: "An important update",
            isRead: false,
            container: container,
            fts5Manager: fts5Manager
        )

        var filters = SearchFilters()
        filters.isRead = false
        let query = SearchQuery(text: "important", filters: filters)
        let results = await useCase.execute(query: query, engine: nil)

        #expect(results.count == 1)
        #expect(results[0].emailId == "email-unread")
        #expect(results[0].isRead == false)
    }

    // MARK: - Test: Filter-only search without text

    @Test("Filter-only search without text returns matching emails")
    func filterOnlySearchWithoutText() async throws {
        let container = try makeContainer()
        let fts5Dir = try makeTempFTS5Dir()
        let (useCase, fts5Manager, _) = try await makeSUT(container: container, fts5Dir: fts5Dir)

        try await insertEmail(
            id: "email-promo-1",
            subject: "Flash Sale",
            bodyPlain: "Limited time sale",
            aiCategory: AICategory.promotions.rawValue,
            container: container,
            fts5Manager: fts5Manager
        )

        try await insertEmail(
            id: "email-primary-1",
            subject: "Hello Friend",
            bodyPlain: "Personal message",
            aiCategory: AICategory.primary.rawValue,
            container: container,
            fts5Manager: fts5Manager
        )

        var filters = SearchFilters()
        filters.category = .promotions
        let query = SearchQuery(text: "", filters: filters)
        let results = await useCase.execute(query: query, engine: nil)

        #expect(results.count == 1)
        #expect(results[0].emailId == "email-promo-1")
    }

    // MARK: - Test: SearchRepositoryImpl delegates correctly

    @Test("SearchRepositoryImpl delegates to use case")
    func repositoryImplDelegates() async throws {
        let container = try makeContainer()
        let fts5Dir = try makeTempFTS5Dir()
        let (useCase, fts5Manager, _) = try await makeSUT(container: container, fts5Dir: fts5Dir)

        try await insertEmail(
            id: "email-repo",
            subject: "Repository Test",
            bodyPlain: "Testing repository layer",
            container: container,
            fts5Manager: fts5Manager
        )

        let repo = SearchRepositoryImpl(searchUseCase: useCase)
        let query = SearchQuery(text: "repository")
        let results = try await repo.searchEmails(query: query, engine: nil)

        #expect(results.count == 1)
        #expect(results[0].emailId == "email-repo")
    }

    // MARK: - Test: Multiple filters combine with AND logic

    @Test("Multiple filters combine with AND logic")
    func multipleFiltersCombine() async throws {
        let container = try makeContainer()
        let fts5Dir = try makeTempFTS5Dir()
        let (useCase, fts5Manager, _) = try await makeSUT(container: container, fts5Dir: fts5Dir)

        // Email matching both filters
        try await insertEmail(
            id: "email-match",
            subject: "Report Summary",
            bodyPlain: "Summary of quarterly report",
            fromAddress: "alice@example.com",
            fromName: "Alice",
            isRead: false,
            container: container,
            fts5Manager: fts5Manager
        )

        // Email matching sender but not read status
        try await insertEmail(
            id: "email-partial",
            subject: "Report Details",
            bodyPlain: "Detailed report analysis",
            fromAddress: "alice@example.com",
            fromName: "Alice",
            isRead: true,
            container: container,
            fts5Manager: fts5Manager
        )

        var filters = SearchFilters()
        filters.sender = "alice"
        filters.isRead = false
        let query = SearchQuery(text: "report", filters: filters)
        let results = await useCase.execute(query: query, engine: nil)

        #expect(results.count == 1)
        #expect(results[0].emailId == "email-match")
    }
}
