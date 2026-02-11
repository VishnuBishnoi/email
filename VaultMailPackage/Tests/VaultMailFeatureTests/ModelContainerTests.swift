import Testing
import SwiftData
@testable import VaultMailFeature

/// Verify ModelContainerFactory initializes correctly (AC-F-02).
@Suite("ModelContainer")
struct ModelContainerTests {

    @Test("In-memory container initializes with all 7 model types")
    func inMemoryContainerCreation() throws {
        let container = try ModelContainerFactory.createForTesting()
        // If we get here without throwing, the schema is valid
        #expect(container.schema.entities.count >= 7)
    }

    @Test("Container schema includes all required entities")
    func schemaContainsAllEntities() throws {
        let container = try ModelContainerFactory.createForTesting()
        let entityNames = container.schema.entities.map { $0.name }
        let requiredEntities = ["Account", "Folder", "Email", "Thread", "EmailFolder", "Attachment", "SearchIndex"]
        for name in requiredEntities {
            #expect(entityNames.contains(name), "Schema missing entity: \(name)")
        }
    }

    @Test("ModelContext can be created from container")
    func modelContextCreation() throws {
        let container = try ModelContainerFactory.createForTesting()
        let context = ModelContext(container)
        // Verify context is usable by performing a simple fetch
        let descriptor = FetchDescriptor<Account>()
        let accounts = try context.fetch(descriptor)
        #expect(accounts.isEmpty)
    }
}
