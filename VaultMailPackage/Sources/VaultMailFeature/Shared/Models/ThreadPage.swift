import Foundation

/// A page of threads returned by paginated queries.
///
/// Used by FetchThreadsUseCase for cursor-based pagination.
/// Spec ref: Thread List spec FR-TL-01 (Pagination)
public struct ThreadPage: @unchecked Sendable {
    /// Threads in this page
    public let threads: [Thread]
    /// Cursor for next page (latestDate of last thread), nil if no more pages
    public let nextCursor: Date?
    /// Whether more pages exist beyond this one
    public let hasMore: Bool

    public init(threads: [Thread], nextCursor: Date?, hasMore: Bool) {
        self.threads = threads
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }

    /// Empty page (no results)
    public static let empty = ThreadPage(threads: [], nextCursor: nil, hasMore: false)
}
