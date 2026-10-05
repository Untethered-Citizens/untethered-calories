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
        BrandFont.styleNavigationBars()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

/// Shows the first-launch flow once, then the main screen. On a cold launch, the branded
/// welcome moment plays over it first.
struct RootView: View {
    @State private var onboarded = AppSettings().hasCompletedOnboarding
    @State private var showingWelcome = true

    var body: some View {
        ZStack {
            Group {
                if onboarded {
                    ContentView()
                } else {
                    OnboardingView {
                        AppSettings().hasCompletedOnboarding = true
                        withAnimation { onboarded = true }
                    }
                }
            }
            if showingWelcome {
                WelcomeMoment {
                    withAnimation(.easeOut(duration: 0.35)) { showingWelcome = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .font(.barlow(.body))
        .tint(Palette.green)
    }
}
