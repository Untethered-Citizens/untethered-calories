import Foundation
import Testing
@testable import CalorieTracker

struct TutorialTests {
    @Test func cardCountsAndKeyStepLast() {
        #expect(Tutorial.losingWeight.cards().count == 7)
        let key = Tutorial.aiKey.cards()
        #expect(key.count == 8)
        #expect(key.last?.picture == .addKey)
        #expect(key.filter { $0.picture == .addKey }.count == 1)
    }

    @Test func cardsStayShort() {
        for tutorial in Tutorial.allCases {
            for card in tutorial.cards() {
                let words = card.fullText.split(whereSeparator: \.isWhitespace).count
                #expect(words <= 50, "\(card.title) has \(words) words")
                #expect(!card.fullText.isEmpty)
            }
        }
    }

    @Test func titlesAreUnique() {
        for tutorial in Tutorial.allCases {
            let titles = tutorial.cards().map(\.title)
            #expect(Set(titles).count == titles.count)
        }
    }

    @Test func poundRuleFollowsTheUnit() {
        let both = Tutorial.losingWeight.cards(unit: nil)[1]
        #expect(both.body.contains("pound") && both.body.contains("kilogram"))
        #expect(both.picture == .weekOfDeficit(unit: .lb))
        let lb = Tutorial.losingWeight.cards(unit: .lb)[1]
        #expect(lb.body.contains("3,500") && !lb.body.contains("kilogram"))
        let kg = Tutorial.losingWeight.cards(unit: .kg)[1]
        #expect(kg.body.contains("7,700") && !kg.body.contains("pound"))
        #expect(kg.picture == .weekOfDeficit(unit: .kg))
    }

    @Test func noPlaceholdersOrOldConsoleAddress() {
        for tutorial in Tutorial.allCases {
            for card in tutorial.cards() {
                #expect(!card.fullText.contains("["), "\(card.title) shows a placeholder")
                #expect(!card.fullText.contains("console.anthropic.com"))
                #expect(card.link.map { $0.url.host() == "platform.claude.com" } ?? true)
            }
        }
    }

    @Test func safetyFloorsMatchTheTargetHelper() {
        let safety = Tutorial.losingWeight.cards().last!
        #expect(safety.body.contains("1,200") && safety.body.contains("1,500"))
    }

    @Test func pagingNextAndFinish() {
        var progress = TutorialProgress(tutorial: .losingWeight, context: .onboarding)
        #expect(progress.page == 0 && progress.nextTitle == "Next" && progress.canSkip)
        for _ in 0..<6 { #expect(progress.next() == .stay) }
        #expect(progress.isLast && progress.nextTitle == "Got it" && !progress.canSkip)
        #expect(progress.next() == .finish)
    }

    @Test func swipingIsClamped() {
        var progress = TutorialProgress(tutorial: .aiKey, context: .replay)
        progress.setPage(99)
        #expect(progress.page == 7)
        progress.setPage(-1)
        #expect(progress.page == 0)
    }

    @Test func skippingTheWeightTutorialLeaves() {
        for context in [TutorialContext.onboarding, .replay] {
            var progress = TutorialProgress(tutorial: .losingWeight, context: context)
            #expect(progress.skip() == .finish)
        }
    }

    @Test func skippingTheKeyTutorialInOnboardingStillOffersTheKey() {
        var progress = TutorialProgress(tutorial: .aiKey, context: .onboarding)
        #expect(progress.skip() == .stay)
        #expect(progress.isLast && progress.endsOnKeyStep)
        #expect(progress.nextTitle == "Continue")
    }

    @Test func replayingTheKeyTutorialCloses() {
        var progress = TutorialProgress(tutorial: .aiKey, context: .replay)
        #expect(progress.skip() == .finish)
        progress.setPage(7)
        #expect(progress.nextTitle == "Done")
        #expect(progress.next() == .finish)
    }

    @Test func onboardingOrder() {
        #expect(OnboardingStep.allCases == [.welcome, .losingWeightTutorial, .keyTutorial, .targets])
        #expect(OnboardingStep.welcome.next == .losingWeightTutorial)
        #expect(OnboardingStep.losingWeightTutorial.next == .keyTutorial)
        #expect(OnboardingStep.keyTutorial.next == .targets)
        #expect(OnboardingStep.targets.next == nil)
    }
}
