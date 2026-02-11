import Testing
import Foundation
@testable import VaultMailFeature

// MARK: - Tests

@Suite("RRFMerger Tests")
struct RRFMergerTests {

    // MARK: - Helpers

    /// Small epsilon for floating-point comparisons.
    private let epsilon: Double = 0.0001

    /// Helper to build a RankedItem.
    private func item(_ emailId: String, rank: Int) -> RRFMerger.RankedItem {
        RRFMerger.RankedItem(emailId: emailId, rank: rank)
    }

    // MARK: - Empty Inputs

    @Test("Empty inputs produce empty results")
    func emptyInputs() {
        let results = RRFMerger.merge(keywordResults: [], semanticResults: [])
        #expect(results.isEmpty)
    }

    // MARK: - Keyword Only

    @Test("Keyword-only results all have .keyword matchSource")
    func keywordOnly() {
        let keywords = [
            item("email-1", rank: 1),
            item("email-2", rank: 2),
            item("email-3", rank: 3),
        ]

        let results = RRFMerger.merge(keywordResults: keywords, semanticResults: [])

        #expect(results.count == 3)
        for result in results {
            #expect(result.matchSource == .keyword)
        }
    }

    // MARK: - Semantic Only

    @Test("Semantic-only results all have .semantic matchSource")
    func semanticOnly() {
        let semantics = [
            item("email-a", rank: 1),
            item("email-b", rank: 2),
        ]

        let results = RRFMerger.merge(keywordResults: [], semanticResults: semantics)

        #expect(results.count == 2)
        for result in results {
            #expect(result.matchSource == .semantic)
        }
    }

    // MARK: - Both Sources, Same Email

    @Test("Email appearing in both sources has .both matchSource and combined score")
    func bothSources() {
        let keywords = [item("shared-email", rank: 1)]
        let semantics = [item("shared-email", rank: 2)]

        let results = RRFMerger.merge(keywordResults: keywords, semanticResults: semantics)

        #expect(results.count == 1)

        let result = results[0]
        #expect(result.emailId == "shared-email")
        #expect(result.matchSource == .both)

        // Expected: keywordWeight / (k + rank1) + semanticWeight / (k + rank2)
        // = 1.0 / (60 + 1) + 1.5 / (60 + 2)
        let expectedKeyword = 1.0 / (60.0 + 1.0)
        let expectedSemantic = 1.5 / (60.0 + 2.0)
        let expectedScore = expectedKeyword + expectedSemantic

        #expect(abs(result.score - expectedScore) < epsilon)
    }

    // MARK: - Deduplication

    @Test("Same emailId in both lists produces only one result entry")
    func deduplication() {
        let keywords = [
            item("dup-email", rank: 1),
            item("unique-kw", rank: 2),
        ]
        let semantics = [
            item("dup-email", rank: 1),
            item("unique-sem", rank: 2),
        ]

        let results = RRFMerger.merge(keywordResults: keywords, semanticResults: semantics)

        // 3 unique email IDs: dup-email, unique-kw, unique-sem
        #expect(results.count == 3)

        let dupResults = results.filter { $0.emailId == "dup-email" }
        #expect(dupResults.count == 1)
        #expect(dupResults[0].matchSource == .both)

        let kwOnly = results.first { $0.emailId == "unique-kw" }
        #expect(kwOnly?.matchSource == .keyword)

        let semOnly = results.first { $0.emailId == "unique-sem" }
        #expect(semOnly?.matchSource == .semantic)
    }

    // MARK: - Score Ordering

    @Test("Results are sorted by score in descending order")
    func scoreOrdering() {
        // Rank-1 items should score higher than rank-5 items
        let keywords = [
            item("low-rank", rank: 5),
            item("high-rank", rank: 1),
            item("mid-rank", rank: 3),
        ]

        let results = RRFMerger.merge(keywordResults: keywords, semanticResults: [])

        #expect(results.count == 3)
        // First result should be the highest scoring (rank 1)
        #expect(results[0].emailId == "high-rank")
        #expect(results[1].emailId == "mid-rank")
        #expect(results[2].emailId == "low-rank")

        // Verify scores are strictly descending
        for i in 0..<(results.count - 1) {
            #expect(results[i].score > results[i + 1].score)
        }
    }

    // MARK: - Custom Weights

    @Test("Custom weights shift relative scoring between keyword and semantic results")
    func customWeights() {
        // Same rank-1 item in each source
        let keywords = [item("kw-email", rank: 1)]
        let semantics = [item("sem-email", rank: 1)]

        // Give keyword higher weight than semantic (opposite of defaults)
        let results = RRFMerger.merge(
            keywordResults: keywords,
            semanticResults: semantics,
            keywordWeight: 2.0,
            semanticWeight: 1.0
        )

        #expect(results.count == 2)

        let kwResult = results.first { $0.emailId == "kw-email" }
        let semResult = results.first { $0.emailId == "sem-email" }

        // With keywordWeight=2.0, keyword result should score higher than semantic with weight=1.0
        #expect(kwResult != nil)
        #expect(semResult != nil)
        #expect(kwResult!.score > semResult!.score)

        // Verify exact scores: weight / (k + rank)
        let expectedKw = 2.0 / (60.0 + 1.0)
        let expectedSem = 1.0 / (60.0 + 1.0)
        #expect(abs(kwResult!.score - expectedKw) < epsilon)
        #expect(abs(semResult!.score - expectedSem) < epsilon)
    }

    // MARK: - Score Calculation Validation

    @Test("Score calculation matches RRF formula: weight / (k + rank)")
    func scoreCalculationValidation() {
        let keywords = [item("email-1", rank: 1)]

        let results = RRFMerger.merge(keywordResults: keywords, semanticResults: [])

        #expect(results.count == 1)

        // For k=60, rank=1, keywordWeight=1.0:
        // score = 1.0 / (60.0 + 1.0) = 1.0 / 61.0
        let expectedScore = 1.0 / 61.0
        #expect(abs(results[0].score - expectedScore) < epsilon)
    }

    // MARK: - Custom K Parameter

    @Test("Custom k parameter affects score calculation")
    func customKParameter() {
        let keywords = [item("email-1", rank: 1)]

        let results = RRFMerger.merge(
            keywordResults: keywords,
            semanticResults: [],
            k: 10.0
        )

        #expect(results.count == 1)

        // With k=10, rank=1: score = 1.0 / (10.0 + 1.0)
        let expectedScore = 1.0 / 11.0
        #expect(abs(results[0].score - expectedScore) < epsilon)
    }

    // MARK: - Multiple Ranks Score Correctly

    @Test("Multiple items across both sources produce correct combined scores")
    func multipleRanksCombined() {
        let keywords = [
            item("email-A", rank: 1),
            item("email-B", rank: 2),
        ]
        let semantics = [
            item("email-B", rank: 1),
            item("email-C", rank: 2),
        ]

        let results = RRFMerger.merge(keywordResults: keywords, semanticResults: semantics)

        #expect(results.count == 3)

        let resultA = results.first { $0.emailId == "email-A" }
        let resultB = results.first { $0.emailId == "email-B" }
        let resultC = results.first { $0.emailId == "email-C" }

        // email-A: keyword only at rank 1
        let expectedA = 1.0 / (60.0 + 1.0)
        #expect(resultA != nil)
        #expect(resultA!.matchSource == .keyword)
        #expect(abs(resultA!.score - expectedA) < epsilon)

        // email-B: keyword rank 2 + semantic rank 1
        let expectedB = 1.0 / (60.0 + 2.0) + 1.5 / (60.0 + 1.0)
        #expect(resultB != nil)
        #expect(resultB!.matchSource == .both)
        #expect(abs(resultB!.score - expectedB) < epsilon)

        // email-C: semantic only at rank 2
        let expectedC = 1.5 / (60.0 + 2.0)
        #expect(resultC != nil)
        #expect(resultC!.matchSource == .semantic)
        #expect(abs(resultC!.score - expectedC) < epsilon)

        // email-B (both sources) should rank first due to combined score
        #expect(results[0].emailId == "email-B")
    }

    // MARK: - Default Constants

    @Test("Default constants have expected values")
    func defaultConstants() {
        #expect(abs(RRFMerger.defaultK - 60.0) < epsilon)
        #expect(abs(RRFMerger.defaultKeywordWeight - 1.0) < epsilon)
        #expect(abs(RRFMerger.defaultSemanticWeight - 1.5) < epsilon)
    }

    // MARK: - Large Input

    @Test("Large input with many items merges correctly and maintains order")
    func largeInput() {
        let keywordItems = (1...100).map { item("kw-\($0)", rank: $0) }
        let semanticItems = (1...100).map { item("sem-\($0)", rank: $0) }

        let results = RRFMerger.merge(keywordResults: keywordItems, semanticResults: semanticItems)

        // 200 unique email IDs (no overlap)
        #expect(results.count == 200)

        // Verify descending order
        for i in 0..<(results.count - 1) {
            #expect(results[i].score >= results[i + 1].score)
        }
    }

    // MARK: - Overlapping Large Input

    @Test("Large input with full overlap produces all .both matchSource")
    func largeOverlappingInput() {
        let shared = (1...50).map { item("email-\($0)", rank: $0) }

        let results = RRFMerger.merge(keywordResults: shared, semanticResults: shared)

        #expect(results.count == 50)
        for result in results {
            #expect(result.matchSource == .both)
        }

        // Verify descending order
        for i in 0..<(results.count - 1) {
            #expect(results[i].score >= results[i + 1].score)
        }
    }

    // MARK: - Zero Weight

    @Test("Zero keyword weight makes keyword-only results score zero")
    func zeroKeywordWeight() {
        let keywords = [item("email-1", rank: 1)]
        let semantics = [item("email-2", rank: 1)]

        let results = RRFMerger.merge(
            keywordResults: keywords,
            semanticResults: semantics,
            keywordWeight: 0.0,
            semanticWeight: 1.5
        )

        let kwResult = results.first { $0.emailId == "email-1" }
        let semResult = results.first { $0.emailId == "email-2" }

        #expect(kwResult != nil)
        #expect(abs(kwResult!.score - 0.0) < epsilon)

        #expect(semResult != nil)
        let expectedSem = 1.5 / (60.0 + 1.0)
        #expect(abs(semResult!.score - expectedSem) < epsilon)
    }
}
