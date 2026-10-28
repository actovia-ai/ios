import SwiftUI
import Testing

@testable import ChatFeature

@Suite("Shimmer")
struct ShimmerTests {
    private func call(_ status: AssistantTurn.ToolCallStep.Status) -> AssistantTurn.Step {
        .toolCall(AssistantTurn.ToolCallStep(id: "k", name: "web_fetch", argumentSummary: "https://a.b", status: status))
    }

    @Test func onlyThePendingActiveCallShimmers() {
        #expect(Shimmer.isRunning(call(.pending), isActive: true))
        #expect(!Shimmer.isRunning(call(.pending), isActive: false))  // settled history
        #expect(!Shimmer.isRunning(call(.succeeded), isActive: true))  // finished: stops at once
        #expect(!Shimmer.isRunning(call(.failed), isActive: true))
    }

    @Test func sweepsForTwoSecondsThenRests() {
        #expect(Shimmer.progress(elapsed: 0) == 0)
        #expect(Shimmer.progress(elapsed: 1) == 0.5)
        #expect(Shimmer.progress(elapsed: 2.2) == nil)
        #expect(Shimmer.progress(elapsed: 2.5) == 0)  // the next sweep
        #expect(Shimmer.progress(elapsed: -1) == nil)
    }

    @Test func bandFollowsTextLengthButFitsTheText() {
        #expect(Shimmer.halfBand(length: 20, width: 400) == 40)
        #expect(Shimmer.halfBand(length: 200, width: 100) == 50)
        #expect(Shimmer.halfBand(length: 0, width: 100) == 0)
    }
}
