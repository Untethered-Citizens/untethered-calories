import SwiftUI
import SwiftData

@main
struct CalorieTrackerApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try DataStore.makeContainer()
        } catch {
            fatalError("Could not open the data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
