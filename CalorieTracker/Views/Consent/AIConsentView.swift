import SwiftUI

/// Asks before anything is sent to Anthropic (App Review 5.1.2(i), issue #28). Shown after a
/// key is saved, before the first send if there's no answer yet, and when sharing is turned
/// back on. It names Anthropic and lists everything that can be sent.
/// The answer is stored here; `onAnswer` gets true for Allow.
struct AIConsentView: View {
    var onAnswer: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "paperplane")
                        .font(.title2)
                        .foregroundStyle(Palette.green)
                        .frame(width: 48, height: 48)
                        .background(Palette.track, in: .rect(cornerRadius: 14))
                        .accessibilityHidden(true)
                    Text("Share with Anthropic?")
                        .font(.custom(BrandFont.condensed(.semibold), size: 34, relativeTo: .largeTitle))
                        .accessibilityAddTraits(.isHeader)
                    Text("Logging by conversation uses Claude, made by Anthropic. To work, the app sends Anthropic the information below. It goes straight from this iPhone to your own Anthropic account, which is billed for it. There's no server of ours in between, and we never see it.")
                        .foregroundStyle(Palette.muted)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("What's sent")
                        .font(.barlow(.headline))
                        .padding([.horizontal, .top], 16)
                        .padding(.bottom, 4)
                    ConsentPoint(icon: "text.bubble", text: "What you type or dictate in the Log tab, and the photos you send")
                    ConsentPoint(icon: "target", text: "Today's targets and what you've eaten so far today")
                    ConsentPoint(icon: "star", text: "Your usual meals")
                    ConsentPoint(icon: "calendar", text: "When you ask about earlier days: those days' meals, totals, targets and weights, including weights from Apple Health")
                }
                .padding(.bottom, 8)
                .background(Palette.panel, in: .rect(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.rule))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Nothing is sent until you send a message. Anthropic handles it under your agreement with them.")
                    Text("If you don't allow this, nothing is sent. Today, Week, Weight, Trend and your targets still work; only logging by conversation is off. You can change your mind any time in Settings → Share with Anthropic.")
                    Link("Read our privacy policy", destination: AppLinks.privacy)
                        .foregroundStyle(Palette.green)
                }
                .font(.barlow(.subheadline))
                .foregroundStyle(Palette.muted)
            }
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Palette.background)
        .safeAreaInset(edge: .bottom) {
            BottomBar {
                PrimaryButton(title: "Allow") { answer(true) }
                Button("Don't allow") { answer(false) }
                    .font(.barlow(.headline))
                    .foregroundStyle(Palette.green)
                    .frame(minHeight: 44)
            }
        }
        // An answer is needed: swiping the sheet away would leave the question open.
        .interactiveDismissDisabled()
    }

    private func answer(_ allowed: Bool) {
        let settings = AppSettings()
        if allowed { settings.allowAI() } else { settings.declineAI() }
        onAnswer(allowed)
    }
}

private struct ConsentPoint: View {
    var icon: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Palette.green)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.barlow(.subheadline))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

#Preview {
    AIConsentView { _ in }
}
