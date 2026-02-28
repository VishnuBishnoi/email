import Foundation
import SwiftData

/// Factory for creating configured SwiftData ModelContainers.
///
/// Provides both production (persistent) and in-memory (testing) variants.
///
/// Schema includes all 8 entities from Foundation spec Section 5.1
/// plus Email Detail spec (TrustedSender):
/// Account, Folder, Email, Thread, EmailFolder, Attachment, SearchIndex, TrustedSender
public enum ModelContainerFactory {

    /// All model types in the schema.
    public static let modelTypes: [any PersistentModel.Type] = [
        Account.self,
        Folder.self,
        Email.self,
        Thread.self,
        EmailFolder.self,
        Attachment.self,
        SearchIndex.self,
        TrustedSender.self,
        ContactCacheEntry.self
    ]

    /// Creates a production ModelContainer with persistent storage.
    public static func create() throws -> ModelContainer {
        let schema = Schema(modelTypes)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            try quarantineCorruptedStore(at: configuration.url)

            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                throw RecoveryFailedError(storeURL: configuration.url, underlying: error)
            }
        }
    }

    /// Creates an in-memory ModelContainer for testing.
    public static func createForTesting() throws -> ModelContainer {
        let schema = Schema(modelTypes)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func quarantineCorruptedStore(at storeURL: URL) throws {
        let fileManager = FileManager.default
        let basePath = storeURL.path
        let sidecarPaths = ["-wal", "-shm", "-journal"].map { basePath + $0 }
        let candidatePaths = [basePath] + sidecarPaths
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupDir = storeURL.deletingLastPathComponent().appendingPathComponent("CorruptedStores", isDirectory: true)

        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        for path in candidatePaths {
            guard fileManager.fileExists(atPath: path) else { continue }
            let sourceURL = URL(fileURLWithPath: path)
            let backupURL = backupDir.appendingPathComponent(sourceURL.lastPathComponent + "." + timestamp + ".corrupted")

            do {
                try fileManager.moveItem(at: sourceURL, to: backupURL)
            } catch {
                // If move fails (e.g. cross-volume/permissions), best-effort delete
                // so container recreation has a clean slate.
                try? fileManager.removeItem(at: sourceURL)
            }
        }
    }
}

public struct RecoveryFailedError: LocalizedError {
    let storeURL: URL
    let underlying: Error

    public var errorDescription: String? {
        [
            "SwiftData store recovery failed.",
            "Store URL: \(storeURL.path)",
            "Underlying: \(underlying.localizedDescription)"
        ].joined(separator: " ")
    }
}
