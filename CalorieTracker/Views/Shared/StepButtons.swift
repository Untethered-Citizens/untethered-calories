import SwiftUI

/// The full-width main button at the bottom of onboarding and tutorial screens.
struct PrimaryButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).bold().frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

/// The bottom bar holding a step's main button, with a backing so the content
/// scrolling underneath doesn't show through.
struct BottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 4) { content }
            .frame(maxWidth: .infinity)
            .background(.bar)
    }
}

/// A numbered instruction, like "1  Open the Console".
struct NumberedStep: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.bold())
                .frame(width: 24, height: 24)
                .background(.tint.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            Text(text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }
}
