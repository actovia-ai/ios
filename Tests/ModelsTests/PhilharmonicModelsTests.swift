import Foundation
import Testing

@testable import Models

@Suite("Philharmonic wire models")
struct PhilharmonicModelsTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test("every conversation event decodes to its case; the rest are unknown")
    func decodesEveryEventFromFixture() throws {
        let events = try PhilharmonicFixtures.events.map { try decode(PhilharmonicSseEvent.self, $0) }
        guard events.count == 18 else {
            Issue.record("expected 18 events, got \(events.count)")
            return
        }
        #expect(events[0] == .messageStart(conversationId: "c1", messageId: "m1", role: .pm, agentId: nil))
        #expect(events[1] == .messageDelta(conversationId: "c1", messageId: "m1", delta: "Hello so far"))
        #expect(events[2] == .messageEnd(conversationId: "c1", messageId: "m1"))
        #expect(
            events[3]
                == .toolCard(
                    conversationId: "c1", messageId: "m2", toolName: "web_search", phase: .end,
                    result: .object(["ok": .bool(true)])))
        guard case .agentCard(_, "m3", let card) = events[4] else {
            Issue.record("expected .agentCard")
            return
        }
        #expect(card.state == .blocked)
        #expect(card.steps.first?.status == .ok)
        #expect(card.prompts.count == 2)
        if case .question(let requestId, let questions) = card.prompts[1] {
            #expect(requestId == "r2")
            #expect(questions.first?.options.last?.description == "the other")
        } else {
            Issue.record("expected a question prompt")
        }
        #expect(events[5] == .memberJoined(conversationId: "c1", agentId: "a2"))
        #expect(events[6] == .roundStart(conversationId: "c1", label: "[Scheduled] nightly"))
        #expect(events[7] == .askUser(conversationId: "c1", question: "Which colour?", options: ["Red", "Blue"]))
        #expect(events[8] == .conversationError(conversationId: "c1", error: "No key"))
        #expect(events[9] == .pmStarted(conversationId: "c1"))
        #expect(events[10] == .pmEnded(conversationId: "c1", reason: "done"))
        #expect(
            events[11]
                == .delegationRetry(
                    conversationId: "c1", taskId: "t1", agentId: "a1", attempt: 2, delayMs: 4000, error: "busy"))
        guard case .planCreated(_, let plan) = events[12] else {
            Issue.record("expected .planCreated")
            return
        }
        #expect(plan.status == .active)
        #expect(plan.steps.first?.assignedAgentId == "a1")
        guard case .planStepUpdated(_, "st1", let patch) = events[13] else {
            Issue.record("expected .planStepUpdated")
            return
        }
        #expect(patch.status == .value(.running))
        guard case .planStepAppended(_, let step) = events[14] else {
            Issue.record("expected .planStepAppended")
            return
        }
        #expect(step.title == "Draft")
        #expect(events[15] == .planStatusChanged(conversationId: "c1", status: .completed))
        #expect(events[16] == .unknown(type: "task_status"))
        #expect(events[17] == .unknown(type: "future_event"))
    }

    @Test("a part this build does not know keeps the parts around it")
    func messageWithUnknownPartKeepsTheRest() throws {
        let message = try decode(
            GroupMessage.self,
            #"""
            {"id":"m1","conversationId":"c1","role":"pm","agentId":null,"content":"Done.","parts":[{"kind":"attachment","name":"a.png","url":"data:image/png;base64,AA","contentType":"image/png"},{"kind":"hologram"},{"kind":"decision","delegations":2,"waits":1}],"taskId":null,"roundId":"r1","createdAt":"2026-10-23T01:00:00.000Z"}
            """#)
        #expect(message.parts.count == 3)
        #expect(message.parts[1] == .unknown(kind: "hologram"))
        #expect(message.parts[2] == .decision(delegations: 2, waits: 1))
        #expect(message.roundId == "r1")
    }

    @Test("a message with null parts and an unknown role still decodes")
    func nullPartsAndUnknownRole() throws {
        let message = try decode(
            GroupMessage.self,
            #"{"id":"m1","conversationId":"c1","role":"narrator","agentId":null,"content":"x","parts":null,"taskId":null,"roundId":null,"createdAt":"t"}"#
        )
        #expect(message.parts.isEmpty)
        #expect(message.role == .unknown("narrator"))
    }

    @Test("a step patch tells an absent field from a null one")
    func stepPatchTellsAbsentFromNull() throws {
        let patch = try decode(PlanStepPatch.self, #"{"note":null}"#)
        #expect(patch.note == .null)
        #expect(patch.output == .absent)
        #expect(patch.status == .absent)
    }

    @Test("an answer encodes as the desktop expects")
    func agentAnswerEncodesAsDesktopExpects() throws {
        func json(_ answer: AgentAnswer) throws -> [String: JSONValue] {
            let data = try JSONEncoder().encode(answer)
            return try JSONDecoder().decode([String: JSONValue].self, from: data)
        }
        #expect(try json(.allow) == ["kind": .string("allow")])
        #expect(try json(.deny(reason: "no")) == ["kind": .string("deny"), "reason": .string("no")])
        #expect(try json(.deny(reason: nil)) == ["kind": .string("deny")])
        #expect(
            try json(.answers(["Which?": .one("A"), "q2": .many(["x", "y"])]))
                == [
                    "kind": .string("answers"),
                    "answers": .object(["Which?": .string("A"), "q2": .array([.string("x"), .string("y")])]),
                ])
    }

    @Test("quota times are epoch milliseconds")
    func quotaTimesAreMilliseconds() throws {
        let quota = try decode(
            CliQuota.self,
            #"{"cli":"claude-code","windows":[{"name":"five_hour","usedPercent":42,"resetsAt":1761200000000,"rejected":true}],"state":"rejected","rejectedWindow":"five_hour","overage":false,"asOf":1761190000000}"#
        )
        #expect(quota.windows.first?.resetsAt == 1_761_200_000_000)
        #expect(quota.windows.first?.rejected == true)
        #expect(quota.state == .rejected)
        #expect(quota.asOf == 1_761_190_000_000)
    }

    @Test("a conversation, an employee, a task and the costs decode")
    func listsDecode() throws {
        let conversation = try decode(
            GroupConversation.self,
            #"{"id":"c1","title":"Site","icon":"🎻","memberAgentIds":["a1"],"archived":false,"createdAt":"t","updatedAt":"t","lastMessageAt":"t2","latestMessage":{"role":"pm","content":"Done","agentId":null,"createdAt":"t2"}}"#
        )
        #expect(conversation.latestMessage?.content == "Done")
        let employee = try decode(
            Employee.self,
            #"{"id":"a1","name":"Ada","description":null,"teamId":"t1","avatarSeed":"ada","avatarStyle":null,"model":"opus","provider":null,"runtime":"claude-code","isActive":true,"systemPrompt":"x"}"#
        )
        #expect(employee.runtime == "claude-code")
        let costs = try decode(
            PhilharmonicCosts.self,
            #"{"totalCost":1.5,"totalTokens":1200,"byConversation":[{"conversationId":"c1","cost":1.5,"tokens":1200}],"byAgent":[{"agentId":"a1","cost":1.5,"tokens":1200}],"daily":[{"date":"2026-10-23","cost":1.5,"tokens":1200}]}"#
        )
        #expect(costs.daily.first?.date == "2026-10-23")
        let task = try decode(
            ScheduledTask.self,
            #"{"id":"k1","conversationId":"c1","title":"Nightly","description":null,"status":"pending","priority":"medium","assignedAgentId":null,"cronExpression":"0 3 * * *","runAt":null,"lastRunAt":null,"lastRunStatus":null,"createdAt":"t"}"#
        )
        #expect(task.cronExpression == "0 3 * * *")
        let round = try decode(PmRoundEvent.self, #"{"seq":1,"kind":"tool_call","payload":{"name":"createPlan"},"createdAt":"t"}"#)
        #expect(round.payload == .object(["name": .string("createPlan")]))
    }
}
