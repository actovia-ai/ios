import Models
import Testing

@testable import PhilharmonicFeature

@Suite("RoundDescription (desktop pm-round.test.ts)")
struct RoundDescriptionTests {
    private final class Seq: @unchecked Sendable { var n = 0 }
    private let seq = Seq()

    private func ev(_ kind: String, _ payload: [String: JSONValue]) -> PmRoundEvent {
        defer { seq.n += 1 }
        return PmRoundEvent(seq: seq.n, kind: kind, payload: .object(payload), createdAt: "2026-10-17T10:00:00.000Z")
    }

    private func call(_ id: String, _ name: String, _ args: [String: JSONValue] = [:]) -> PmRoundEvent {
        ev("tool_call", ["toolCallId": .string(id), "name": .string(name), "args": .object(args)])
    }

    private func result(_ id: String, _ name: String, _ text: String, isError: Bool = false) -> PmRoundEvent {
        ev("tool_result", ["toolCallId": .string(id), "name": .string(name), "text": .string(text), "isError": .bool(isError)])
    }

    @Test("pairs each call with its result by toolCallId, in call order")
    func pairsCalls() {
        let lines = RoundDescription.lines(
            [
                ev("input", ["trigger": .string("scheduled"), "text": .string("Daily digest")]),
                ev(
                    "reports",
                    [
                        "messages": .array([
                            .object(["messageId": .string("m1"), "agentId": .string("a1"), "name": .string("Ada")])
                        ])
                    ]),
                ev("thinking", ["text": .string("Let me plan.")]),
                call("t1", "createPlan", ["steps": .array([.object(["title": .string("x")])])]),
                call("t2", "askUser", ["question": .string("?")]),
                result("t2", "askUser", "yes"),
                result("t1", "createPlan", "Plan created", isError: true),
                ev(
                    "usage",
                    [
                        "inputTokens": .number(10), "outputTokens": .number(5), "cacheReadTokens": .number(0),
                        "costUsd": .number(0.01),
                    ]),
                ev("error", ["message": .string("boom"), "aborted": .bool(false)]),
            ], bubbleText: "")
        #expect(
            lines == [
                .trigger(scheduled: true, text: "Daily digest"),
                .reports([.init(messageId: "m1", agentId: "a1", name: "Ada")]),
                .thinking("Let me plan."),
                .call(
                    tool: "createPlan", args: ["steps": .array([.object(["title": .string("x")])])],
                    result: "Plan created", isError: true, refused: false),
                .call(tool: "askUser", args: ["question": .string("?")], result: "yes", isError: false, refused: false),
                .usage(inputTokens: 10, outputTokens: 5, costUsd: 0.01),
                .error(message: "boom", aborted: false),
            ])
    }

    @Test("counts the cached part of the prompt as read — '14 in' was a 32k round")
    func cachedCounts() {
        let lines = RoundDescription.lines(
            [
                ev(
                    "usage",
                    [
                        "inputTokens": .number(14), "outputTokens": .number(3727), "cacheReadTokens": .number(32498),
                        "cacheWriteTokens": .number(100), "costUsd": .number(0.1),
                    ])
            ], bubbleText: "")
        #expect(lines == [.usage(inputTokens: 32612, outputTokens: 3727, costUsd: 0.1)])
    }

    @Test("a call without a result has result nil")
    func callWithoutResult() {
        let lines = RoundDescription.lines([call("t1", "delegateTask", ["employeeId": .string("a1")])], bubbleText: "")
        #expect(
            lines == [
                .call(tool: "delegateTask", args: ["employeeId": .string("a1")], result: nil, isError: false, refused: false)
            ])
    }

    @Test("a delegateTask whose result starts with \"Not started:\" is refused")
    func refusedDelegation() {
        let lines = RoundDescription.lines(
            [
                call("t1", "delegateTask", ["employeeId": .string("a1")]),
                result("t1", "delegateTask", "Not started: the quota is used up"),
                call("t2", "waitForQuota"),
                result("t2", "waitForQuota", "Not started: unrelated"),
            ], bubbleText: "")
        #expect(lines.map(\.isRefusedCall) == [true, false])
    }

    @Test("a waitForQuota whose result starts with \"Refused\" is refused")
    func refusedWait() {
        let lines = RoundDescription.lines(
            [
                call("t1", "waitForQuota"),
                result("t1", "waitForQuota", "Refused: no step s9 in the plan."),
                call("t2", "waitForQuota"),
                result("t2", "waitForQuota", "Step parked. You will be woken at Tue 07:00."),
            ], bubbleText: "")
        #expect(lines.map(\.isRefusedCall) == [true, false])
    }

    @Test("drops the last text line when it is the bubble's own text")
    func dropsBubbleText() {
        let lines = RoundDescription.lines(
            [
                ev("text", ["text": .string("Working on it.")]), call("t1", "createReport"),
                ev("text", ["text": .string(" All done. ")]),
            ], bubbleText: "All done.")
        #expect(lines.count == 2)
        #expect(lines[0] == .text("Working on it."))
    }

    @Test("keeps a last text that differs from the bubble")
    func keepsDifferentText() {
        #expect(RoundDescription.lines([ev("text", ["text": .string("Interim")])], bubbleText: "Final") == [.text("Interim")])
    }

    @Test("reads the reason after \"Refused: \" and the wake time")
    func reasonAndWake() {
        #expect(RoundDescription.waitRefusalReason("Refused: no step s9 in the plan.") == "no step s9 in the plan.")
        #expect(RoundDescription.waitRefusalReason(nil) == "")
        #expect(RoundDescription.wakeTime("Step parked. You will be woken at Tue 07:00. End your turn now.") == "Tue 07:00")
        #expect(RoundDescription.wakeTime("Step parked.") == nil)
        #expect(RoundDescription.wakeTime(nil) == nil)
    }
}
