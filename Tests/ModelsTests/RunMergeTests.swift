import Foundation
import Testing

@testable import Models

private func message(_ json: String) -> ChatMessage {
    try! JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
}

private func user(_ id: String, _ extra: String = "") -> ChatMessage {
    message(#"{"id":"\#(id)","runId":"\#(id)","role":"user","content":"\#(id)","timestamp":1\#(extra)}"#)
}

private func answer(_ id: String, _ runId: String) -> ChatMessage {
    message(#"{"id":"\#(id)","runId":"\#(runId)","role":"assistant","content":[{"type":"text","text":"\#(id)"}],"timestamp":2}"#)
}

/// Protocol 2 (desktop spec 2026-10-01 §C2): `done` carries the run as stored and the regenerate states, not the whole
/// conversation; the phone merges. The same vectors as the desktop's `mergeRun` (`run-merge.test.ts`).
@Suite("RunMerge: a finished run into the conversation the phone holds")
struct RunMergeTests {
    @Test("the run's streamed copies are replaced by the stored run, where they stood")
    func replacesInPlace() {
        let merged = RunMerge.merge(
            [user("u1"), answer("a1", "u1"), user("u2"), answer("tmp", "u2")],
            run: [user("u2", #","stamp":99"#), answer("a2", "u2")],
            attempts: [:])
        #expect(merged.map(\.id) == ["u1", "a1", "u2", "a2"])
        #expect(merged[2].raw["stamp"] == .number(99))
    }

    @Test("every earlier message is kept as it was")
    func keepsEarlier() {
        let earlier = answer("a1", "u1")
        let merged = RunMerge.merge([user("u1"), earlier, user("u2")], run: [user("u2"), answer("a2", "u2")], attempts: [:])
        #expect(merged[1] == earlier)
    }

    @Test("every run takes its stored regenerate state")
    func appliesAttempts() {
        let merged = RunMerge.merge(
            [user("u1", #","attempt":"comparing""#), answer("a1", "u1"), user("u2")],
            run: [user("u2", #","alternateOf":"u1","attempt":"comparing""#), answer("a2", "u2")],
            attempts: ["u1": .folded, "u2": .chosen])
        #expect(merged.filter { $0.role == "user" }.map { [$0.id, $0.attempt?.rawValue ?? "-"] } == [
            ["u1", "folded"], ["u2", "chosen"],
        ])
    }

    @Test("a run the phone had not shown yet goes at the end")
    func appends() {
        let merged = RunMerge.merge([user("u1")], run: [user("u2"), answer("a2", "u2")], attempts: [:])
        #expect(merged.map(\.id) == ["u1", "u2", "a2"])
    }
}
