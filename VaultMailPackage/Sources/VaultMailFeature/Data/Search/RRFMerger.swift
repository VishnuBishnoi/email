import Foundation

/// Reciprocal Rank Fusion (RRF) merger for combining keyword and semantic search rankings.
///
/// RRF formula: score(d) = Σ (weight_i / (k + rank_i))
/// where rank_i is 1-based position in ranked list i.
///
/// Spec ref: FR-SEARCH-05
public enum RRFMerger {

    /// Default k parameter — controls how much emphasis is given to top-ranked items.
    /// Higher k = more uniform weighting across ranks.
    public static let defaultK: Double = 60.0

    /// Default weight for keyword (FTS5/BM25) results.
    public static let defaultKeywordWeight: Double = 1.0

    /// Default weight for semantic (embedding/cosine) results.
    public static let defaultSemanticWeight: Double = 1.5

    /// A ranked item from a single search source.
    public struct RankedItem: Sendable {
        /// Email ID (used for deduplication)
        public let emailId: String
        /// 1-based rank in the source list
        public let rank: Int

        public init(emailId: String, rank: Int) {
            self.emailId = emailId
            self.rank = rank
        }
    }

    /// Result after RRF fusion.
    public struct MergedResult: Sendable {
        /// Email ID
        public let emailId: String
        /// Combined RRF score (higher = better)
        public let score: Double
        /// Which sources matched this email
        public let matchSource: MatchSource

        public init(emailId: String, score: Double, matchSource: MatchSource) {
            self.emailId = emailId
            self.score = score
            self.matchSource = matchSource
        }
    }

    /// Merge keyword and semantic ranked lists using Reciprocal Rank Fusion.
    ///
    /// - Parameters:
    ///   - keywordResults: Ranked list from FTS5/BM25 search (best first)
    ///   - semanticResults: Ranked list from semantic/cosine search (best first)
    ///   - k: RRF k parameter (default: 60)
    ///   - keywordWeight: Weight for keyword source (default: 1.0)
    ///   - semanticWeight: Weight for semantic source (default: 1.5)
    /// - Returns: Merged results sorted by combined RRF score (descending)
    public static func merge(
        keywordResults: [RankedItem],
        semanticResults: [RankedItem],
        k: Double = defaultK,
        keywordWeight: Double = defaultKeywordWeight,
        semanticWeight: Double = defaultSemanticWeight
    ) -> [MergedResult] {
        // Build score map
        var scores: [String: (score: Double, hasKeyword: Bool, hasSemantic: Bool)] = [:]

        for item in keywordResults {
            let rrf = keywordWeight / (k + Double(item.rank))
            var entry = scores[item.emailId] ?? (score: 0, hasKeyword: false, hasSemantic: false)
            entry.score += rrf
            entry.hasKeyword = true
            scores[item.emailId] = entry
        }

        for item in semanticResults {
            let rrf = semanticWeight / (k + Double(item.rank))
            var entry = scores[item.emailId] ?? (score: 0, hasKeyword: false, hasSemantic: false)
            entry.score += rrf
            entry.hasSemantic = true
            scores[item.emailId] = entry
        }

        // Build results
        return scores.map { emailId, entry in
            let source: MatchSource
            if entry.hasKeyword && entry.hasSemantic {
                source = .both
            } else if entry.hasSemantic {
                source = .semantic
            } else {
                source = .keyword
            }
            return MergedResult(emailId: emailId, score: entry.score, matchSource: source)
        }
        .sorted { $0.score > $1.score }
    }
}
