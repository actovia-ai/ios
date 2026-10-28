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

    /// Frames of the sweep for the controller to look at, when a `.dd` folder is there to hold them.
    @MainActor @Test func rendersFrames() throws {
        let dir = URL(filePath: "/Users/yanceyleo/Code/actovia/ios-shimmer/.dd/shots")
        guard FileManager.default.fileExists(atPath: dir.deletingLastPathComponent().path) else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = "Web Fetch: https://www.federalreserve.gov/news…"
        for (scheme, name) in [(ColorScheme.light, "light"), (.dark, "dark")] {
            for (index, progress) in [0.0, 0.25, 0.5, 0.75, 1.0].enumerated() {
                let label = Text(verbatim: text).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                let view = label
                    .overlay { ShimmerBand(length: text.count, frozenProgress: progress).mask(label) }
                    .padding(12)
                    .background(scheme == .dark ? Color.black : Color.white)
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                let png = try #require(renderer.uiImage?.pngData())
                try png.write(to: dir.appending(path: "shimmer-\(name)-\(index).png"))
            }
        }
    }
}
