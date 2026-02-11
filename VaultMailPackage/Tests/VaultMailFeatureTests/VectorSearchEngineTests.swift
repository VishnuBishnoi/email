import Testing
import Foundation
@testable import VaultMailFeature

@Suite("VectorSearchEngine Tests")
struct VectorSearchEngineTests {

    // MARK: - Helpers

    /// Unit vectors used across multiple tests.
    /// These are pre-normalized so dot product == cosine similarity.
    private let v1: [Float] = [1.0, 0.0, 0.0]        // unit vector along x
    private let v2: [Float] = [0.0, 1.0, 0.0]        // unit vector along y
    private let v3: [Float] = [0.707, 0.707, 0.0]    // 45 degrees between x and y

    // MARK: - Empty corpus

    @Test("search on empty corpus returns empty results")
    func searchEmptyCorpus() async {
        let engine = VectorSearchEngine()
        let query: [Float] = [1.0, 0.0, 0.0]

        let results = await engine.search(query: query)

        #expect(results.isEmpty)
    }

    // MARK: - Ordering

    @Test("search returns results in correct similarity order")
    func searchReturnsCorrectOrdering() async {
        let engine = VectorSearchEngine()

        await engine.loadVectors(from: [
            VectorEntry(emailId: "email-1", embedding: v1),
            VectorEntry(emailId: "email-2", embedding: v2),
            VectorEntry(emailId: "email-3", embedding: v3),
        ])

        // Query along x axis — email-1 should be most similar (dot=1.0),
        // email-3 next (~0.707), email-2 last (dot=0.0).
        let query: [Float] = [1.0, 0.0, 0.0]
        let results = await engine.search(query: query)

        #expect(results.count == 3)
        #expect(results[0].emailId == "email-1")
        #expect(results[1].emailId == "email-3")
        #expect(results[2].emailId == "email-2")

        // Verify similarity values are in expected ranges.
        #expect(results[0].similarity > 0.99)         // ~1.0
        #expect(results[1].similarity > 0.70)         // ~0.707
        #expect(results[2].similarity < 0.01)         // ~0.0
    }

    // MARK: - Remove single vector

    @Test("removeVector removes the correct entry")
    func removeVector() async {
        let engine = VectorSearchEngine()

        await engine.addVector(emailId: "a", embedding: v1)
        await engine.addVector(emailId: "b", embedding: v2)
        #expect(await engine.count == 2)

        await engine.removeVector(emailId: "a")
        #expect(await engine.count == 1)

        // Only email-b should remain.
        let results = await engine.search(query: v2)
        #expect(results.count == 1)
        #expect(results[0].emailId == "b")
    }

    // MARK: - Remove all

    @Test("removeAll clears all vectors")
    func removeAll() async {
        let engine = VectorSearchEngine()

        await engine.loadVectors(from: [
            VectorEntry(emailId: "x", embedding: v1),
            VectorEntry(emailId: "y", embedding: v2),
            VectorEntry(emailId: "z", embedding: v3),
        ])
        #expect(await engine.count == 3)

        await engine.removeAll()
        #expect(await engine.count == 0)

        let results = await engine.search(query: v1)
        #expect(results.isEmpty)
    }

    // MARK: - Limit

    @Test("search respects the limit parameter")
    func searchRespectsLimit() async {
        let engine = VectorSearchEngine()

        await engine.loadVectors(from: [
            VectorEntry(emailId: "e1", embedding: v1),
            VectorEntry(emailId: "e2", embedding: v2),
            VectorEntry(emailId: "e3", embedding: v3),
        ])

        let results = await engine.search(query: v1, limit: 2)

        #expect(results.count == 2)
        // Top 2 should still be in descending similarity order.
        #expect(results[0].emailId == "e1")
        #expect(results[1].emailId == "e3")
    }

    // MARK: - Dimension mismatch

    @Test("mismatched dimensions are silently skipped")
    func mismatchedDimensionsSkipped() async {
        let engine = VectorSearchEngine()

        // Add vectors with different dimensions.
        let short: [Float] = [1.0, 0.0]               // 2-dim
        let correct: [Float] = [0.0, 1.0, 0.0]        // 3-dim
        let long: [Float] = [1.0, 0.0, 0.0, 0.0]     // 4-dim

        await engine.addVector(emailId: "short", embedding: short)
        await engine.addVector(emailId: "correct", embedding: correct)
        await engine.addVector(emailId: "long", embedding: long)
        #expect(await engine.count == 3)

        // Query with 3-dim — only "correct" should match.
        let query: [Float] = [0.0, 1.0, 0.0]
        let results = await engine.search(query: query)

        #expect(results.count == 1)
        #expect(results[0].emailId == "correct")
        #expect(results[0].similarity > 0.99)
    }

    // MARK: - addVector replaces duplicate

    @Test("addVector replaces existing entry with same emailId")
    func addVectorReplacesDuplicate() async {
        let engine = VectorSearchEngine()

        await engine.addVector(emailId: "dup", embedding: v1)
        await engine.addVector(emailId: "dup", embedding: v2)

        // Should still be 1 entry, not 2.
        #expect(await engine.count == 1)

        // The stored vector should be v2 (most recently added).
        let results = await engine.search(query: v2)
        #expect(results.count == 1)
        #expect(results[0].emailId == "dup")
        #expect(results[0].similarity > 0.99)
    }
}
