import SwiftUI
import SwiftData
import PrivateMailFeature

@main
struct PrivateMailApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainerFactory.create()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
