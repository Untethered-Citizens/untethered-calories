import SwiftUI
import SwiftData

/// The home screen. For now that's the logging screen; the dashboard tabs arrive in Phase 4.
struct ContentView: View {
    var body: some View {
        LogView()
    }
}

#Preview {
    ContentView()
        .modelContainer(try! DataStore.makeContainer(inMemory: true))
}
