import Foundation
import Testing
@testable import VaultMailFeature

@Suite("QueryContactsUseCase")
@MainActor
struct QueryContactsUseCaseTests {

    // MARK: - Helpers

    private static func makeSUT() -> (QueryContactsUseCase, MockEmailRepository) {
        let repo = MockEmailRepository()
        let useCase = QueryContactsUseCase(repository: repo)
        return (useCase, repo)
    }

    private static func makeContact(
        email: String,
        accountId: String = "acc1",
        displayName: String? = nil,
        frequency: Int = 1
    ) -> ContactCacheEntry {
        ContactCacheEntry(
            accountId: accountId,
            emailAddress: email,
            displayName: displayName,
            lastSeenDate: Date(),
            frequency: frequency
        )
    }

    // MARK: - Empty Prefix

    @Test("Empty prefix returns empty array")
    func emptyPrefixReturnsEmpty() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.contactEntries = [Self.makeContact(email: "test@example.com")]

        let results = try await useCase.queryContacts(prefix: "", accountIds: ["acc1"])
        let count = results.count

        #expect(count == 0)
        #expect(repo.queryContactsCallCount == 0)
    }

    // MARK: - Basic Query

    @Test("Queries repository with prefix and returns matching contacts")
    func basicQuery() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.contactEntries = [
            Self.makeContact(email: "alice@example.com", displayName: "Alice"),
            Self.makeContact(email: "bob@example.com", displayName: "Bob"),
        ]

        let results = try await useCase.queryContacts(prefix: "ali", accountIds: ["acc1"])
        let count = results.count
        let firstEmail = results.first?.emailAddress

        #expect(count == 1)
        #expect(firstEmail == "alice@example.com")
        #expect(repo.queryContactsCallCount == 1)
    }

    // MARK: - Multi-Account Deduplication

    @Test("Deduplicates contacts across accounts by email, keeping highest frequency")
    func multiAccountDedup() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.contactEntries = [
            Self.makeContact(email: "shared@example.com", accountId: "acc1", frequency: 5),
            Self.makeContact(email: "shared@example.com", accountId: "acc2", frequency: 10),
        ]

        let results = try await useCase.queryContacts(prefix: "sha", accountIds: ["acc1", "acc2"])
        let count = results.count
        let firstFreq = results.first?.frequency

        #expect(count == 1)
        #expect(firstFreq == 10)
        #expect(repo.queryContactsCallCount == 2)
    }

    // MARK: - Sorting

    @Test("Results are sorted by frequency descending")
    func sortedByFrequency() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.contactEntries = [
            Self.makeContact(email: "test-low@example.com", frequency: 1),
            Self.makeContact(email: "test-high@example.com", frequency: 100),
            Self.makeContact(email: "test-mid@example.com", frequency: 10),
        ]

        let results = try await useCase.queryContacts(prefix: "test", accountIds: ["acc1"])
        let count = results.count
        let freqs = results.map(\.frequency)

        #expect(count == 3)
        #expect(freqs == [100, 10, 1])
    }

    // MARK: - Limit

    @Test("Returns at most contactAutocompleteLimitItems results")
    func respectsLimit() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.contactEntries = (0..<20).map { i in
            Self.makeContact(email: "user\(i)@example.com", frequency: 20 - i)
        }

        let results = try await useCase.queryContacts(prefix: "user", accountIds: ["acc1"])
        let count = results.count

        #expect(count <= AppConstants.contactAutocompleteLimitItems)
    }

    // MARK: - Error Handling

    @Test("Wraps repository errors as ComposerError.contactQueryFailed")
    func errorWrapping() async {
        let (useCase, repo) = Self.makeSUT()
        repo.errorToThrow = NSError(domain: "test", code: 42)

        do {
            let _ = try await useCase.queryContacts(prefix: "test", accountIds: ["acc1"])
            #expect(Bool(false), "Expected error to be thrown")
        } catch {
            #expect(error is ComposerError)
        }
    }

    // MARK: - No Accounts

    @Test("Empty accountIds returns empty results")
    func noAccounts() async throws {
        let (useCase, repo) = Self.makeSUT()
        repo.contactEntries = [Self.makeContact(email: "test@example.com")]

        let results = try await useCase.queryContacts(prefix: "test", accountIds: [])
        let count = results.count

        #expect(count == 0)
        #expect(repo.queryContactsCallCount == 0)
    }
}
