import Models
import Testing

@testable import PhilharmonicFeature

@Suite("BusyAgents (desktop busy-reducer.test.ts)")
struct BusyAgentsTests {
    private let c = "c1"

    @Test("marks the PM busy on pm_started and clears on pm_ended")
    func pmStartedEnded() {
        var s = BusyAgents()
        s.apply(.pmStarted(conversationId: c))
        #expect(s.label(for: BusyAgents.pm) == .orchestrating)
        s.apply(.pmEnded(conversationId: c, reason: "done"))
        #expect(s.label(for: BusyAgents.pm) == nil)
    }

    @Test("tracks an employee from message_start through message_end")
    func employeeStartEnd() {
        var s = BusyAgents()
        s.apply(.messageStart(conversationId: c, messageId: "m1", role: .employee, agentId: "a1"))
        #expect(s.label(for: "a1") == .thinking)
        s.apply(.messageEnd(conversationId: c, messageId: "m1"))
        #expect(s.label(for: "a1") == nil)
    }

    @Test("uses tool_card to flip the activity label and back")
    func toolCardFlips() {
        var s = BusyAgents()
        s.apply(.messageStart(conversationId: c, messageId: "m1", role: .employee, agentId: "a1"))
        s.apply(.toolCard(conversationId: c, messageId: "m1", toolName: "web_search", phase: .start, result: nil))
        #expect(s.label(for: "a1") == .running("web_search"))
        s.apply(.toolCard(conversationId: c, messageId: "m1", toolName: "web_search", phase: .end, result: nil))
        #expect(s.label(for: "a1") == .thinking)
    }

    @Test("attributes pm tool cards to the PM sentinel")
    func pmToolCards() {
        var s = BusyAgents()
        s.apply(.pmStarted(conversationId: c))
        s.apply(.messageStart(conversationId: c, messageId: "m1", role: .pm, agentId: nil))
        s.apply(
            .toolCard(conversationId: c, messageId: "m1", toolName: "search_knowledge_base", phase: .start, result: nil))
        #expect(s.label(for: BusyAgents.pm) == .running("search_knowledge_base"))
    }

    @Test("user and system messages do not mark anyone busy")
    func userAndSystem() {
        var s = BusyAgents()
        s.apply(.messageStart(conversationId: c, messageId: "mu", role: .user, agentId: nil))
        s.apply(.messageStart(conversationId: c, messageId: "ms", role: .system, agentId: nil))
        #expect(s.isEmpty)
    }

    @Test("keeps an employee busy if a second in-flight message still references them")
    func secondInFlight() {
        var s = BusyAgents()
        s.apply(.messageStart(conversationId: c, messageId: "m1", role: .employee, agentId: "a1"))
        s.apply(.messageStart(conversationId: c, messageId: "m2", role: .employee, agentId: "a1"))
        s.apply(.messageEnd(conversationId: c, messageId: "m1"))
        #expect(s.label(for: "a1") != nil)
        s.apply(.messageEnd(conversationId: c, messageId: "m2"))
        #expect(s.label(for: "a1") == nil)
    }

    @Test("clears everything on conversation_error")
    func clearsOnError() {
        var s = BusyAgents()
        s.apply(.pmStarted(conversationId: c))
        s.apply(.messageStart(conversationId: c, messageId: "m1", role: .employee, agentId: "a1"))
        s.apply(.conversationError(conversationId: c, error: "boom"))
        #expect(s.isEmpty)
    }

    @Test("keeps the PM busy across multiple message starts until pm_ended")
    func pmAcrossMessages() {
        var s = BusyAgents()
        s.apply(.pmStarted(conversationId: c))
        s.apply(.messageStart(conversationId: c, messageId: "pm1", role: .pm, agentId: nil))
        s.apply(.messageEnd(conversationId: c, messageId: "pm1"))
        #expect(s.label(for: BusyAgents.pm) == .orchestrating)
        s.apply(.pmEnded(conversationId: c, reason: "done"))
        #expect(s.label(for: BusyAgents.pm) == nil)
    }
}
