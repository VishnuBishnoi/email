import Foundation
import SwiftData

/// Implementation of SearchRepositoryProtocol using hybrid FTS5 + semantic search.
///
/// Thin wrapper that delegates to ``SearchEmailsUseCase`` for the actual
/// search orchestration. This layer exists to keep the protocol boundary
/// clean and allow DI in tests.
///
/// Spec ref: FR-SEARCH-05
@MainActor
public final class SearchRepositoryImpl: SearchRepositoryProtocol {

    private let searchUseCase: SearchEmailsUseCase

    /// Creates a SearchRepositoryImpl.
    ///
    /// - Parameter searchUseCase: The use case that performs hybrid search orchestration.
    public init(searchUseCase: SearchEmailsUseCase) {
        self.searchUseCase = searchUseCase
    }

    public func searchEmails(
        query: SearchQuery,
        engine: (any AIEngineProtocol)?
    ) async throws -> [SearchResult] {
        await searchUseCase.execute(query: query, engine: engine)
    }
}
