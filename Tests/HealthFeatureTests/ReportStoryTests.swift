import Models
import Testing

@testable import HealthFeature

struct ReportStoryTests {
    typealias Run = ReportText.Run

    @Test func cutsTheSentenceAroundItsHighlights() {
        let runs = ReportText.runs("HRV 38 ms, still recovering.", highlights: ["still recovering", "38 ms"])
        #expect(runs == [
            Run(text: "HRV ", isHighlight: false), Run(text: "38 ms", isHighlight: true),
            Run(text: ", ", isHighlight: false), Run(text: "still recovering", isHighlight: true),
            Run(text: ".", isHighlight: false),
        ])
    }

    @Test func leavesAMissingOrOverlappingHighlightPlain() {
        #expect(ReportText.runs("5,840 steps", highlights: ["7,000", ""]) == [Run(text: "5,840 steps", isHighlight: false)])
        #expect(ReportText.runs("5,840 steps", highlights: ["5,840 steps", "steps"]) == [Run(text: "5,840 steps", isHighlight: true)])
    }

    @Test func anEmptySentenceHasNoRuns() {
        #expect(ReportText.runs("", highlights: ["x"]).isEmpty)
    }

    @MainActor @Test func storiesSkipCategoriesTheAppDoesNotKnow() {
        var s = PreviewSummaryService.sample
        s.insights = [.init(category: "mood", text: "x"), .init(category: "body", text: "Three cups.")]
        #expect(ReportText.stories(s).map(\.0) == [.body])
        s.insights = [.init(category: "mood", text: "x")]
        #expect(ReportStory(s) == nil)
        s.insights = nil
        #expect(ReportStory(s) == nil)
    }

    @Test func theGalleryNoteIsAStory() {
        let s = PreviewSummaryService.sample
        #expect(ReportText.stories(s).map(\.0) == [.sleep, .recovery, .activity])
        #expect(s.headlineHighlight.map(s.headline.contains) == true)
        for i in s.insights ?? [] { for h in i.highlights { #expect(i.text.contains(h)) } }
    }

    @MainActor @Test func everyCategoryHasItsOwnNoteIcon() {
        #expect(CategoryStyle.of(.sleep).symbol == "moon.zzz.fill")
        #expect(CategoryStyle.of(.activity).symbol == "figure.walk")
        #expect(CategoryStyle.of(.recovery).symbol == "heart.text.square.fill")
        #expect(CategoryStyle.of(.body).symbol == "drop.fill")
    }
}

@Suite("The note's headline under the hero")
struct HeadlineAfterHeroTests {
    @Test("a headline that opens with the hero's words keeps only what follows them")
    func dropsTheHerosWords() {
        #expect(
            ReportText.headline("A little under-slept, so take it easy.", after: "A little under-slept")
                == "So take it easy.")
        #expect(ReportText.headline("a little UNDER-SLEPT — rest today", after: "A little under-slept") == "Rest today")
    }

    @Test("a headline that is only the hero's words is not shown")
    func nothingLeft() {
        #expect(ReportText.headline("A little under-slept.", after: "A little under-slept") == nil)
    }

    @Test("any other headline is kept whole")
    func keepsOthers() {
        #expect(ReportText.headline("Slept well, moved little.", after: "A little under-slept") == "Slept well, moved little.")
        #expect(ReportText.headline("Rest: a little under-slept", after: "A little under-slept") == "Rest: a little under-slept")
    }
}
