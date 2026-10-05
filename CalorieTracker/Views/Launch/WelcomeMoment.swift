import SwiftUI

/// About a second of brand on a cold launch (D65). It starts exactly where the static launch
/// screen leaves off (the mark centred on the brand ground), lifts the mark, shows the name,
/// then hands over. With Reduce Motion the mark stays put and the name simply fades in.
struct WelcomeMoment: View {
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    /// Matches the launch screen's mark, so the hand-off is seamless.
    private let launchMarkSize: CGFloat = 150

    var body: some View {
        ZStack {
            Palette.brand.ignoresSafeArea()
            Image("LaunchMark")
                .resizable()
                .frame(width: launchMarkSize, height: launchMarkSize)
                .scaleEffect(revealed && !reduceMotion ? 0.85 : 1)
                .offset(y: revealed && !reduceMotion ? -70 : 0)
            VStack(spacing: 8) {
                Text("Untethered Calories")
                    .font(.custom(BrandFont.condensed(.semibold), size: 44, relativeTo: .largeTitle))
                Text("AI food log · your own key")
                    .font(.barlow(.subheadline, weight: .medium))
                    .opacity(0.85)
            }
            .foregroundStyle(Palette.plate)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 24)
            .offset(y: reduceMotion ? 140 : 90)
            .opacity(revealed ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Untethered Calories")
        .task {
            withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.6, bounce: 0.15)) {
                revealed = true
            }
            try? await Task.sleep(for: .seconds(1.1))
            onDone()
        }
    }
}

#Preview {
    WelcomeMoment {}
}
