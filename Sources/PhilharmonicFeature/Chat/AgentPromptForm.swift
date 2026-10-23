import Models

/// A coding agent's question form, as the desktop's `QuestionPrompt` fills it in.
public enum AgentPromptForm {
    /// Picks, then the free text (trimmed), as one answer per question: Claude Code (no id) takes one string, the
    /// picks joined; Codex (an id) takes each as its own.
    public static func answer(
        for questions: [AgentQuestion], picked: [String: [String]], other: [String: String]
    ) -> AgentAnswer {
        var answers: [String: AgentAnswer.Value] = [:]
        for question in questions {
            let given = given(question, picked: picked, other: other)
            answers[question.answerKey] = question.id == nil ? .one(given.joined(separator: ", ")) : .many(given)
        }
        return .answers(answers)
    }

    public static func isComplete(
        _ questions: [AgentQuestion], picked: [String: [String]], other: [String: String]
    ) -> Bool {
        questions.allSatisfy { !given($0, picked: picked, other: other).isEmpty }
    }

    /// A choice tapped: it replaces a single choice, and toggles in a multiple one.
    public static func toggled(_ current: [String], _ label: String, in question: AgentQuestion) -> [String] {
        guard question.multiSelect else { return [label] }
        return current.contains(label) ? current.filter { $0 != label } : current + [label]
    }

    /// Closed choices get no free text; a question without options is free-form, and a secret is typed.
    public static func offersFreeText(_ question: AgentQuestion) -> Bool {
        question.isSecret == true || question.options.isEmpty || question.isOther != false
    }

    private static func given(
        _ question: AgentQuestion, picked: [String: [String]], other: [String: String]
    ) -> [String] {
        let text = other[question.answerKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (picked[question.answerKey] ?? []) + (text.isEmpty ? [] : [text])
    }
}
