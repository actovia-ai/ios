import Models
import Testing

@testable import PhilharmonicFeature

/// The desktop's `QuestionPrompt` (agent-card-prompts.tsx): what a filled-in question form sends.
@Suite("AgentPromptForm")
struct AgentPromptAnswerTests {
    private let options = [AgentQuestion.Option(label: "A"), AgentQuestion.Option(label: "B")]

    @Test("Claude Code's question (no id) answers one string, picks joined")
    func noIdAnswersAString() {
        let single = AgentQuestion(question: "Which?", options: options)
        #expect(
            AgentPromptForm.answer(for: [single], picked: ["Which?": ["A"]], other: [:])
                == .answers(["Which?": .one("A")]))
        let multi = AgentQuestion(question: "Which ones?", multiSelect: true, options: options)
        #expect(
            AgentPromptForm.answer(for: [multi], picked: ["Which ones?": ["B", "A"]], other: [:])
                == .answers(["Which ones?": .one("B, A")]))
    }

    @Test("Codex's question (an id) answers an array, keyed by the id")
    func idAnswersAnArrayKeyedById() {
        let question = AgentQuestion(id: "q1", question: "Which?", options: options)
        #expect(
            AgentPromptForm.answer(for: [question], picked: ["q1": ["A"]], other: [:])
                == .answers(["q1": .many(["A"])]))
    }

    @Test("free text is one more answer after the picks, trimmed; blank is none")
    func otherTextFollowsThePicks() {
        let question = AgentQuestion(question: "Which?", multiSelect: true, options: options)
        #expect(
            AgentPromptForm.answer(for: [question], picked: ["Which?": ["A"]], other: ["Which?": "  mine "])
                == .answers(["Which?": .one("A, mine")]))
        #expect(
            AgentPromptForm.answer(for: [question], picked: [:], other: ["Which?": "mine"])
                == .answers(["Which?": .one("mine")]))
        #expect(!AgentPromptForm.isComplete([question], picked: [:], other: ["Which?": "   "]))
    }

    @Test("complete once every question has an answer")
    func completeNeedsEveryQuestion() {
        let first = AgentQuestion(question: "One?", options: options)
        let second = AgentQuestion(question: "Two?", options: options)
        #expect(!AgentPromptForm.isComplete([first, second], picked: ["One?": ["A"]], other: [:]))
        #expect(AgentPromptForm.isComplete([first, second], picked: ["One?": ["A"], "Two?": ["B"]], other: [:]))
    }

    @Test("a pick replaces a single choice and toggles a multiple one")
    func toggleFollowsMultiSelect() {
        let single = AgentQuestion(question: "Which?", options: options)
        #expect(AgentPromptForm.toggled(["A"], "B", in: single) == ["B"])
        let multi = AgentQuestion(question: "Which?", multiSelect: true, options: options)
        #expect(AgentPromptForm.toggled(["A"], "B", in: multi) == ["A", "B"])
        #expect(AgentPromptForm.toggled(["A", "B"], "A", in: multi) == ["B"])
    }

    @Test("closed choices get no free text; a secret or a question without options does")
    func freeTextRule() {
        #expect(!AgentPromptForm.offersFreeText(AgentQuestion(isOther: false, question: "Q", options: options)))
        #expect(AgentPromptForm.offersFreeText(AgentQuestion(question: "Q", options: options)))
        #expect(AgentPromptForm.offersFreeText(AgentQuestion(isOther: false, question: "Q")))
        #expect(
            AgentPromptForm.offersFreeText(AgentQuestion(isOther: false, isSecret: true, question: "Q", options: options)))
    }
}
