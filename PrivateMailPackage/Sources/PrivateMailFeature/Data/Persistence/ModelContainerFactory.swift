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
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        return try ModelContainer(for: schema, configurations: [configuration])
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
}
