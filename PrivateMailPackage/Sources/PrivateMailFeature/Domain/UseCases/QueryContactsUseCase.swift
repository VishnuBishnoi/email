import Foundation

/// Use case for querying the local contact cache for autocomplete.
///
/// Per FR-COMP-04, contacts are sourced exclusively from synced email
/// headers. NO system Contacts access, NO external lookups.
///
/// Spec ref: Email Composer spec FR-COMP-04
@MainActor
public protocol QueryContactsUseCaseProtocol {
    /// Query contacts matching a prefix, sorted by frequency.
    /// - Parameters:
    ///   - prefix: The text prefix to match against email/name.
    ///   - accountIds: Account IDs to search across (multi-account merge).
    /// - Returns: Deduplicated contacts sorted by frequency.
    func queryContacts(prefix: String, accountIds: [String]) async throws -> [ContactCacheEntry]
}

/// Default implementation of `QueryContactsUseCaseProtocol`.
///
/// Queries across multiple accounts and deduplicates by email address,
/// keeping the highest frequency and most recent display name.
///
/// Spec ref: Email Composer spec FR-COMP-04
@MainActor
public final class QueryContactsUseCase: QueryContactsUseCaseProtocol {

    private let repository: EmailRepositoryProtocol

    public init(repository: EmailRepositoryProtocol) {
        self.repository = repository
    }

    public func queryContacts(prefix: String, accountIds: [String]) async throws -> [ContactCacheEntry] {
        guard !prefix.isEmpty else { return [] }
        do {
            var allResults: [ContactCacheEntry] = []
            for accountId in accountIds {
                let results = try await repository.queryContacts(
                    accountId: accountId,
                    prefix: prefix,
                    limit: AppConstants.contactAutocompleteLimitItems * 2  // Over-fetch for dedup
                )
                allResults.append(contentsOf: results)
            }

            // Deduplicate by email address (case-insensitive), keep highest frequency
            var deduped: [String: ContactCacheEntry] = [:]
            for entry in allResults {
                let key = entry.emailAddress.lowercased()
                if let existing = deduped[key] {
                    if entry.frequency > existing.frequency {
                        deduped[key] = entry
                    } else if entry.frequency == existing.frequency,
                              entry.lastSeenDate > existing.lastSeenDate {
                        deduped[key] = entry
                    }
                } else {
                    deduped[key] = entry
                }
            }

            // Sort by frequency DESC, return limited results
            let sorted = deduped.values.sorted { $0.frequency > $1.frequency }
            return Array(sorted.prefix(AppConstants.contactAutocompleteLimitItems))
        } catch {
            throw ComposerError.contactQueryFailed(error.localizedDescription)
        }
    }
}
