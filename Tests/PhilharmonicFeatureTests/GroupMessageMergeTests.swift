import Models
import Testing

@testable import PhilharmonicFeature

@Suite("GroupMessageMerge (desktop merge-group-messages.test.ts)")
struct GroupMessageMergeTests {
    @Test("shows a step once: its saved row and its live bubble share an id, and the live card wins")
    func savedAndLiveShareAnId() {
        let saved = Fx.card(queued: true)
        let latest = Fx.card(state: .blocked, prompts: [Fx.prompt])
        let merged = GroupMessageMerge.merge(
            history: [Fx.row("m1", card: saved)], live: [Fx.live("m1", card: latest)], liveCards: ["m1": latest])
        #expect(merged.count == 1)
        #expect(merged.first?.id == "m1")
        #expect(merged.first?.agentCard == latest)
        #expect(merged.first?.isLive == false)
    }

    @Test("after a reload the saved card alone carries its prompt")
    func savedCardAlone() {
        let merged = GroupMessageMerge.merge(
            history: [Fx.row("m1", card: Fx.card(state: .blocked, prompts: [Fx.prompt]))], live: [], liveCards: [:])
        #expect(merged.first?.agentCard?.prompts == [Fx.prompt])
        #expect(merged.first?.agentCardSuperseded == false)
    }

    @Test("marks every card of a session but its latest as superseded")
    func supersededCards() {
        let merged = GroupMessageMerge.merge(
            history: [
                Fx.row("m1", card: Fx.card(state: .done)),
                Fx.row("m2", card: Fx.card(sessionId: "s2", state: .done)),
                Fx.row("m3", card: Fx.card(state: .working)),
            ],
            live: [Fx.live("m4", card: Fx.card(sessionId: "s2"))], liveCards: [:])
        #expect(merged.map(\.id) == ["m1", "m2", "m3", "m4"])
        #expect(merged.map(\.agentCardSuperseded) == [true, true, false, false])
    }

    @Test("history parts become attachments, artifacts and the first decision")
    func partsLifted() {
        let merged = GroupMessageMerge.merge(
            history: [
                Fx.row(
                    "m1", role: .pm, content: "Done.",
                    parts: [
                        .attachment(name: "a.png", url: "data:image/png;base64,AA", contentType: "image/png"),
                        .artifact(artifactId: "x", title: "Report", code: "<p>"),
                        .decision(delegations: 2, waits: 0), .decision(delegations: 9, waits: 9),
                    ])
            ], live: [], liveCards: [:])
        let bubble = merged[0]
        #expect(bubble.attachments.map(\.name) == ["a.png"])
        #expect(bubble.artifacts.map(\.title) == ["Report"])
        #expect(bubble.decision == GroupDecision(delegations: 2, waits: 0))
        #expect(bubble.text == "Done.")
    }

    @Test("a live bubble's ended artifact tool row shows its artifact before the row is saved")
    func liveArtifact() {
        let row = ToolRow(
            toolName: "createReport", phase: .end,
            result: .object([
                "type": .string("artifact"), "artifactId": .string("x"), "title": .string("Report"),
                "code": .string("<p>"),
            ]))
        let started = ToolRow(toolName: "createReport", phase: .start, result: nil)
        let merged = GroupMessageMerge.merge(history: [], live: [Fx.live("m9", toolRows: [started, row])], liveCards: [:])
        #expect(merged.first?.artifacts == [ArtifactPart(artifactId: "x", title: "Report", code: "<p>")])
        #expect(merged.first?.isLive == true)
        #expect(merged.first?.toolRows.count == 2)
    }
}
