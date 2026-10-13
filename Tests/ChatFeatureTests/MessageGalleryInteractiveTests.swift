#if DEBUG
import Testing

@testable import ChatFeature

@Suite("MessageGalleryFixtures: the interactive blocks' runs")
struct MessageGalleryInteractiveTests {
    @Test("the interactive runs are named, in order, at the end; the code run sits just before them; another name is none")
    func namedSections() {
        let count = MessageGalleryFixtures.runs.count
        let names = MessageGalleryFixtures.interactiveNames
        #expect(names == ["ask", "confirm", "answered", "steps", "entity", "stock"])
        #expect(MessageGalleryFixtures.interactiveRuns.count == names.count)
        for (offset, name) in names.enumerated() {
            #expect(MessageGalleryFixtures.namedSection(name) == count - names.count + offset, "\(name)")
        }
        #expect(MessageGalleryFixtures.namedSection("code") == count - names.count - MessageGalleryFixtures.codeRuns.count)
        #expect(MessageGalleryFixtures.namedSection("questionnaire") == nil)
    }

    @Test("the steps run's pictures are thumbnails its own search returned, so the gallery shows them")
    func stepsPictures() throws {
        let index = try #require(MessageGalleryFixtures.namedSection("steps"))
        let segments = MessageGalleryFixtures.segments(MessageGalleryFixtures.runs[index].json)
        let turn = try #require(
            segments.compactMap { if case .assistantTurn(let turn) = $0, turn.body.contains("```exodus-steps") { turn } else { nil } }.first)
        let placed = try #require(InteractiveRendering.placed(in: [turn.body]))
        guard case .steps(let block) = placed.fence.block else { return #expect(Bool(false)) }
        let pictures = StepsPictures(sources: turn.sources, media: turn.foot.searchMedia)
        #expect(block.steps.compactMap(pictures.url(for:)).count == 2)
    }

    @Test("Copy of the stock run's answer is its words, not its JSON")
    func stockCopy() throws {
        let index = try #require(MessageGalleryFixtures.namedSection("stock"))
        let segments = MessageGalleryFixtures.segments(MessageGalleryFixtures.runs[index].json)
        let turn = try #require(
            segments.compactMap { if case .assistantTurn(let turn) = $0, turn.body.contains("```exodus-stock") { turn } else { nil } }.first)
        let copied = CopiedAnswer.text(of: turn)
        #expect(copied.contains("NASDAQ:AAPL \u{2014} "))
        #expect(!copied.contains("exodus-stock"))
    }

    @Test("the answered run's answer names the run of its questionnaire, so the block is drawn frozen")
    func answeredFreezes() throws {
        let index = try #require(MessageGalleryFixtures.namedSection("answered"))
        let segments = MessageGalleryFixtures.segments(MessageGalleryFixtures.runs[index].json)
        let asking = try #require(
            segments.compactMap { segment -> AssistantTurn? in
                if case .assistantTurn(let turn) = segment, turn.body.contains("```exodus-ask") { turn } else { nil }
            }.first)
        let answer = try #require(
            segments.compactMap { segment -> InteractiveAnswer.Head? in
                if case .user(let message) = segment { InteractiveAnswer.split(message.answerText).head } else { nil }
            }.first)
        #expect(answer.ref == asking.runId)
        #expect(InteractiveRendering.answers(in: segments)[asking.runId] != nil)
    }
}
#endif
