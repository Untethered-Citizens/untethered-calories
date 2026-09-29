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
            RootView()
        }
        .modelContainer(container)
    }
}

/// Shows the first-launch flow once, then the main screen.
struct RootView: View {
    @State private var onboarded = AppSettings().hasCompletedOnboarding

    var body: some View {
        if onboarded {
            ContentView()
        } else {
            OnboardingView {
                AppSettings().hasCompletedOnboarding = true
                withAnimation { onboarded = true }
            }
        }
    }
}
