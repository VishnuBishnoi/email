import Testing
import Foundation
import CryptoKit
@testable import PrivateMailFeature

@Suite("ModelManager")
struct ModelManagerTests {

    // MARK: - Helpers

    private static func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelManagerTest-\(UUID().uuidString)")
    }

    private static func cleanUp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Available Models

    @Test("availableModels returns all registered models")
    func availableModelsCount() async {
        let tempDir = Self.makeTempDir()
        let manager = ModelManager(modelsDirectory: tempDir)

        let models = await manager.availableModels()
        #expect(models.count == 2, "Should have Qwen3-1.7B and Qwen3-0.6B")

        let ids = models.map(\.info.id)
        #expect(ids.contains("qwen3-1.7b-q4km"))
        #expect(ids.contains("qwen3-0.6b-q4km"))

        Self.cleanUp(tempDir)
    }

    @Test("all models have Apache 2.0 license")
    func modelsHaveApacheLicense() async {
        let tempDir = Self.makeTempDir()
        let manager = ModelManager(modelsDirectory: tempDir)

        let models = await manager.availableModels()
        for model in models {
            #expect(model.info.license == "Apache 2.0")
        }

        Self.cleanUp(tempDir)
    }

    @Test("availableModels shows notDownloaded for fresh directory")
    func freshModelsAreNotDownloaded() async {
        let tempDir = Self.makeTempDir()
        let manager = ModelManager(modelsDirectory: tempDir)

        let models = await manager.availableModels()
        for model in models {
            #expect(model.status == .notDownloaded)
        }

        Self.cleanUp(tempDir)
    }

    // MARK: - Storage Usage

    @Test("storageUsage returns 0 for empty directory")
    func emptyStorageUsage() async {
        let tempDir = Self.makeTempDir()
        let manager = ModelManager(modelsDirectory: tempDir)

        let usage = await manager.storageUsage()
        #expect(usage == 0)

        Self.cleanUp(tempDir)
    }

    @Test("storageUsage reports file sizes accurately")
    func storageUsageAccurate() async throws {
        let tempDir = Self.makeTempDir()
        let manager = ModelManager(modelsDirectory: tempDir)

        // Create a dummy file
        let dummyFile = tempDir.appendingPathComponent("test.gguf")
        let data = Data(repeating: 0xAB, count: 1024)
        try data.write(to: dummyFile)

        let usage = await manager.storageUsage()
        #expect(usage == 1024, "Should report 1024 bytes for the dummy file")

        Self.cleanUp(tempDir)
    }

    // MARK: - Delete Model

    @Test("deleteModel removes file from disk")
    func deleteModelRemovesFile() async throws {
        let tempDir = Self.makeTempDir()
        let manager = ModelManager(modelsDirectory: tempDir)

        // Get a model info and create a fake file
        let info = ModelManager.availableModelInfos[0]
        let path = await manager.modelPath(for: info)
        let data = Data(repeating: 0xFF, count: 512)
        try data.write(to: path)

        #expect(FileManager.default.fileExists(atPath: path.path))

        try await manager.deleteModel(id: info.id)

        #expect(!FileManager.default.fileExists(atPath: path.path))

        Self.cleanUp(tempDir)
    }

    @Test("deleteModel updates status to notDownloaded")
    func deleteModelUpdatesStatus() async throws {
        let tempDir = Self.makeTempDir()
        let manager = ModelManager(modelsDirectory: tempDir)

        let info = ModelManager.availableModelInfos[0]
        let path = await manager.modelPath(for: info)
        try Data(repeating: 0xFF, count: 512).write(to: path)

        try await manager.deleteModel(id: info.id)

        let models = await manager.availableModels()
        let model = models.first { $0.id == info.id }
        #expect(model?.status == .notDownloaded)

        Self.cleanUp(tempDir)
    }

    @Test("deleteModel throws for unknown model ID")
    func deleteModelThrowsForUnknown() async {
        let tempDir = Self.makeTempDir()
        let manager = ModelManager(modelsDirectory: tempDir)

        await #expect(throws: AIEngineError.self) {
            try await manager.deleteModel(id: "nonexistent-model")
        }

        Self.cleanUp(tempDir)
    }

    // MARK: - Integrity Verification

    @Test("verifyIntegrity passes with matching checksum")
    func integrityPassesWithMatchingChecksum() async throws {
        let tempDir = Self.makeTempDir()
        let manager = ModelManager(modelsDirectory: tempDir)

        let testData = Data("Hello, World!".utf8)
        let testFile = tempDir.appendingPathComponent("test_model.gguf")
        try testData.write(to: testFile)

        let digest = SHA256.hash(data: testData)
        let expectedHash = digest.map { String(format: "%02x", $0) }.joined()

        let result = try await manager.verifyIntegrity(path: testFile, sha256: expectedHash)
        #expect(result)

        Self.cleanUp(tempDir)
    }

    @Test("verifyIntegrity fails and deletes file with mismatched checksum")
    func integrityFailsWithMismatch() async throws {
        let tempDir = Self.makeTempDir()
        let manager = ModelManager(modelsDirectory: tempDir)

        let testFile = tempDir.appendingPathComponent("corrupt_model.gguf")
        try Data("Some data".utf8).write(to: testFile)

        #expect(FileManager.default.fileExists(atPath: testFile.path))

        await #expect(throws: AIEngineError.self) {
            try await manager.verifyIntegrity(path: testFile, sha256: "0000000000000000")
        }

        // File should be deleted per AC-A-03
        #expect(!FileManager.default.fileExists(atPath: testFile.path),
                "Corrupt file should be deleted after integrity check failure")

        Self.cleanUp(tempDir)
    }

    @Test("verifyIntegrity throws for missing file")
    func integrityThrowsForMissingFile() async {
        let tempDir = Self.makeTempDir()
        let manager = ModelManager(modelsDirectory: tempDir)

        let missingFile = tempDir.appendingPathComponent("missing.gguf")

        await #expect(throws: AIEngineError.self) {
            try await manager.verifyIntegrity(path: missingFile, sha256: "abc123")
        }

        Self.cleanUp(tempDir)
    }

    // MARK: - isModelDownloaded

    @Test("isModelDownloaded returns false when file does not exist")
    func notDownloaded() async {
        let tempDir = Self.makeTempDir()
        let manager = ModelManager(modelsDirectory: tempDir)

        let result = await manager.isModelDownloaded(id: "qwen3-1.7b-q4km")
        #expect(!result)

        Self.cleanUp(tempDir)
    }

    @Test("isModelDownloaded returns true when file exists")
    func downloaded() async throws {
        let tempDir = Self.makeTempDir()
        let manager = ModelManager(modelsDirectory: tempDir)

        let info = ModelManager.availableModelInfos[0]
        let path = await manager.modelPath(for: info)
        try Data(repeating: 0xFF, count: 100).write(to: path)

        let result = await manager.isModelDownloaded(id: info.id)
        #expect(result)

        Self.cleanUp(tempDir)
    }

    // MARK: - Model Info

    @Test("formattedSize returns human-readable string")
    func formattedSize() {
        let info = ModelManager.availableModelInfos[0]
        let formatted = info.formattedSize
        #expect(!formatted.isEmpty)
        // Should contain "GB" or "MB"
        #expect(formatted.contains("B"), "Should contain byte unit")
    }

    @Test("modelPath returns unique path per model")
    func uniqueModelPaths() async {
        let tempDir = Self.makeTempDir()
        let manager = ModelManager(modelsDirectory: tempDir)

        let path1 = await manager.modelPath(forID: "qwen3-1.7b-q4km")
        let path2 = await manager.modelPath(forID: "qwen3-0.6b-q4km")

        #expect(path1 != path2, "Different models should have different paths")
        #expect(path1 != nil)
        #expect(path2 != nil)

        Self.cleanUp(tempDir)
    }
}
