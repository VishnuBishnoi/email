import Foundation
import Testing
@testable import PrivateMailFeature

@Suite("FTS5Manager")
struct FTS5ManagerTests {

    // MARK: - Helpers

    private func makeSUT() throws -> (FTS5Manager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FTS5Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let manager = FTS5Manager(databaseDirectoryURL: tempDir)
        return (manager, tempDir)
    }

    private func cleanup(_ tempDir: URL) {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Lifecycle

    @Test("open creates database and sets isOpen to true")
    func openCreatesDatabase() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        let beforeOpen = await manager.isOpen
        #expect(beforeOpen == false)

        try await manager.open()
        let afterOpen = await manager.isOpen
        #expect(afterOpen == true)
    }

    @Test("close sets isOpen to false")
    func closeDatabase() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        await manager.close()
        let isOpen = await manager.isOpen
        #expect(isOpen == false)
    }

    @Test("close is idempotent and does not crash when called twice")
    func closeIdempotent() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        await manager.close()
        await manager.close() // Should not crash
        let isOpen = await manager.isOpen
        #expect(isOpen == false)
    }

    @Test("insert before open throws databaseNotOpen")
    func insertBeforeOpenThrows() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        await #expect(throws: FTS5Error.self) {
            try await manager.insert(
                emailId: "e1", accountId: "a1",
                subject: "Test", body: "Body",
                senderName: "Alice", senderEmail: "alice@example.com"
            )
        }
    }

    // MARK: - Insert / Delete

    @Test("insert email then search finds it")
    func insertEmail() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        try await manager.insert(
            emailId: "e1", accountId: "a1",
            subject: "Budget Review", body: "Please review the Q3 budget.",
            senderName: "Alice", senderEmail: "alice@company.com"
        )

        let results = try await manager.search(query: "budget")
        #expect(results.count == 1)
        #expect(results.first?.emailId == "e1")
        #expect(results.first?.accountId == "a1")
    }

    @Test("insert with same emailId replaces existing entry")
    func insertReplacesExisting() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        try await manager.insert(
            emailId: "e1", accountId: "a1",
            subject: "Original", body: "First body",
            senderName: "Alice", senderEmail: "alice@co.com"
        )
        try await manager.insert(
            emailId: "e1", accountId: "a1",
            subject: "Updated Subject", body: "Second body",
            senderName: "Alice", senderEmail: "alice@co.com"
        )

        let results = try await manager.search(query: "Updated")
        #expect(results.count == 1)
        #expect(results.first?.emailId == "e1")

        // Old content should not be findable
        let oldResults = try await manager.search(query: "Original")
        #expect(oldResults.isEmpty)
    }

    @Test("delete email removes it from search results")
    func deleteEmail() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        try await manager.insert(
            emailId: "e1", accountId: "a1",
            subject: "Delete Me", body: "Body",
            senderName: "Alice", senderEmail: "alice@co.com"
        )

        try await manager.delete(emailId: "e1")

        let results = try await manager.search(query: "Delete")
        #expect(results.isEmpty)
    }

    @Test("deleteAll removes all entries for a specific account")
    func deleteAllForAccount() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        try await manager.insert(
            emailId: "e1", accountId: "a1",
            subject: "Email One", body: "Body one",
            senderName: "Alice", senderEmail: "alice@co.com"
        )
        try await manager.insert(
            emailId: "e2", accountId: "a1",
            subject: "Email Two", body: "Body two",
            senderName: "Alice", senderEmail: "alice@co.com"
        )
        try await manager.insert(
            emailId: "e3", accountId: "a2",
            subject: "Email Three", body: "Body three",
            senderName: "Bob", senderEmail: "bob@co.com"
        )

        try await manager.deleteAll(accountId: "a1")

        // Account a1 emails should be gone
        let results1 = try await manager.search(query: "Email")
        #expect(results1.count == 1)
        #expect(results1.first?.accountId == "a2")
    }

    // MARK: - Search

    @Test("search matches subject text")
    func searchBySubject() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        try await manager.insert(
            emailId: "e1", accountId: "a1",
            subject: "Quarterly Revenue Report", body: "See attached.",
            senderName: "Finance", senderEmail: "finance@co.com"
        )

        let results = try await manager.search(query: "Revenue")
        #expect(results.count == 1)
    }

    @Test("search matches body text")
    func searchByBody() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        try await manager.insert(
            emailId: "e1", accountId: "a1",
            subject: "Update", body: "The kubernetes cluster has been migrated.",
            senderName: "DevOps", senderEmail: "devops@co.com"
        )

        let results = try await manager.search(query: "kubernetes")
        #expect(results.count == 1)
    }

    @Test("search matches sender name")
    func searchBySenderName() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        try await manager.insert(
            emailId: "e1", accountId: "a1",
            subject: "Hello", body: "Hi",
            senderName: "Bartholomew", senderEmail: "bart@co.com"
        )

        let results = try await manager.search(query: "Bartholomew")
        #expect(results.count == 1)
    }

    @Test("search matches sender email")
    func searchBySenderEmail() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        try await manager.insert(
            emailId: "e1", accountId: "a1",
            subject: "Hello", body: "Hi",
            senderName: "Alice", senderEmail: "alice.wonderland@co.com"
        )

        let results = try await manager.search(query: "wonderland")
        #expect(results.count == 1)
    }

    @Test("search supports prefix matching (search-as-you-type)")
    func searchPrefixMatching() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        try await manager.insert(
            emailId: "e1", accountId: "a1",
            subject: "Budget Planning", body: "Annual budget discussion.",
            senderName: "Finance", senderEmail: "finance@co.com"
        )

        // "budg" should match "budget" via prefix *
        let results = try await manager.search(query: "budg")
        #expect(results.count == 1)
    }

    @Test("search respects limit parameter")
    func searchLimitRespected() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        for i in 1...5 {
            try await manager.insert(
                emailId: "e\(i)", accountId: "a1",
                subject: "Meeting \(i)", body: "Agenda for meeting \(i).",
                senderName: "Alice", senderEmail: "alice@co.com"
            )
        }

        let results = try await manager.search(query: "meeting", limit: 2)
        #expect(results.count == 2)
    }

    @Test("search with empty query throws invalidQuery")
    func searchEmptyQueryThrows() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()

        await #expect(throws: FTS5Error.self) {
            _ = try await manager.search(query: "")
        }
    }

    @Test("search sanitizes special FTS5 characters")
    func searchSanitizesSpecialChars() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        try await manager.insert(
            emailId: "e1", accountId: "a1",
            subject: "Testing Queries", body: "Some body text.",
            senderName: "Alice", senderEmail: "alice@co.com"
        )

        // These special chars should be stripped, leaving "Testing"
        let results = try await manager.search(query: "\"Test*ing()\"")
        #expect(results.count == 1)
    }

    // MARK: - Highlight

    @Test("highlight wraps matched terms in bold tags")
    func highlightWrapsMatchInBoldTags() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        try await manager.insert(
            emailId: "e1", accountId: "a1",
            subject: "Budget Review Meeting", body: "Discuss the budget.",
            senderName: "Finance", senderEmail: "finance@co.com"
        )

        let highlighted = try await manager.highlight(
            emailId: "e1",
            column: .subject,
            query: "budget"
        )

        #expect(highlighted != nil)
        #expect(highlighted?.contains("<b>") == true)
        #expect(highlighted?.contains("</b>") == true)
    }

    @Test("highlight returns nil for non-existent email")
    func highlightReturnsNilForMissing() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        try await manager.open()
        try await manager.insert(
            emailId: "e1", accountId: "a1",
            subject: "Test", body: "Body",
            senderName: "Alice", senderEmail: "alice@co.com"
        )

        let result = try await manager.highlight(
            emailId: "nonexistent",
            column: .subject,
            query: "test"
        )
        #expect(result == nil)
    }

    // MARK: - Error: operations on closed database

    @Test("search before open throws databaseNotOpen")
    func searchBeforeOpenThrows() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        await #expect(throws: FTS5Error.self) {
            _ = try await manager.search(query: "test")
        }
    }

    @Test("delete before open throws databaseNotOpen")
    func deleteBeforeOpenThrows() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        await #expect(throws: FTS5Error.self) {
            try await manager.delete(emailId: "e1")
        }
    }

    @Test("deleteAll before open throws databaseNotOpen")
    func deleteAllBeforeOpenThrows() async throws {
        let (manager, tempDir) = try makeSUT()
        defer { cleanup(tempDir) }

        await #expect(throws: FTS5Error.self) {
            try await manager.deleteAll(accountId: "a1")
        }
    }
}
