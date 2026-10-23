import MarkdownKit
import Models
import SwiftUI

/// A coding agent's run in the group (the desktop's `AgentCardView`): the CLI and its folder, the state, the last
/// steps, what it wrote, and the prompts waiting for the owner.
struct AgentCardView: View {
    let card: AgentCard
    let model: GroupChatViewModel

    var body: some View {
        let visible = AgentCardWording.visibleSteps(card)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(verbatim: AgentCardWording.cliName(card.runtime) + (card.model.map { " (\($0))" } ?? ""))
                    .fontWeight(.medium)
                    .layoutPriority(1)
                Text(verbatim: card.projectName + (card.branch.map { " · \($0)" } ?? ""))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    if card.state == .working, !card.queued { ProgressView().controlSize(.mini) }
                    stateText
                }
                .foregroundStyle(card.state == .error ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .layoutPriority(1)
            }
            .font(.caption)
            if !visible.shown.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    if visible.hidden > 0 {
                        Text(Self.moreSteps(visible.hidden))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(visible.shown) { step in
                        HStack(spacing: 6) {
                            stepGlyph(step.status)
                            Text(verbatim: AgentCardWording.cliToolLabel(step.tool))
                                .fontWeight(.medium)
                                .layoutPriority(1)
                            if !step.summary.isEmpty {
                                Text(verbatim: AgentCardWording.relativeSummary(step.summary, cwd: card.cwd))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                .font(.caption)
            }
            let text = (card.blocks + [card.pending]).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n\n")
            if !text.isEmpty {
                MarkdownView(text: text, isStreaming: card.state == .working)
            }
            ForEach(card.prompts.filter { $0.requestId.map { !model.settledPrompts.contains($0) } ?? false },
                id: \.requestId) { prompt in
                switch prompt {
                case .permission(_, let tool, let summary, let detail):
                    PermissionPromptView(card: card, prompt: prompt, tool: tool, summary: summary, detail: detail, model: model)
                case .question(_, let questions):
                    QuestionPromptView(card: card, prompt: prompt, questions: questions, model: model)
                case .unknown:
                    EmptyView()
                }
            }
            if let error = card.error {
                Text(verbatim: error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            ForEach(Array(card.notices.enumerated()), id: \.offset) { _, notice in
                Text(verbatim: notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if card.continuedInTerminal {
                Text("philharmonic:agents.card.inTerminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator))
    }

    /// The catalog picks the plural form; the branch only gives the English its singular.
    private static func moreSteps(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "philharmonic:agents.card.moreSteps", defaultValue: "\(count) earlier step")
        }
        return String(localized: "philharmonic:agents.card.moreSteps", defaultValue: "\(count) earlier steps")
    }

    @ViewBuilder private var stateText: some View {
        switch AgentCardWording.stateKey(card) {
        case "queued": Text("philharmonic:agents.card.state.queued")
        case "waiting": Text("philharmonic:agents.card.state.waiting")
        case "done": Text("philharmonic:agents.card.state.done")
        case "stopped": Text("philharmonic:agents.card.state.stopped")
        case "failed": Text("philharmonic:agents.card.state.failed")
        default: Text("philharmonic:agents.card.state.working")
        }
    }

    @ViewBuilder private func stepGlyph(_ status: AgentCard.Step.Status) -> some View {
        switch status {
        case .running: ProgressView().controlSize(.mini)
        case .ok: Image(systemName: "checkmark").foregroundStyle(.green)
        case .error: Image(systemName: "xmark").foregroundStyle(.red)
        case .unknown: Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }
}

/// "Claude Code wants to use Bash", everything it would run whole, and Allow / Deny.
private struct PermissionPromptView: View {
    let card: AgentCard
    let prompt: AgentPrompt
    let tool: String
    let summary: String
    let detail: String
    let model: GroupChatViewModel

    @State private var reason = ""
    @State private var sending = false

    var body: some View {
        let name = AgentCardWording.cliName(card.runtime)
        let toolName = AgentCardWording.cliToolLabel(tool)
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "philharmonic:agents.card.wantsTo", defaultValue: "\(name) wants to use \(toolName)"))
                .font(.subheadline)
            if !summary.isEmpty {
                Text(verbatim: summary)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            // Everything the owner is approving, whole — never clipped.
            ScrollView {
                Text(verbatim: detail)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .background(.background.opacity(0.6), in: .rect(cornerRadius: 10))
            // Codex's decline carries no words, so it is not asked for one.
            if card.runtime == "claude-code" {
                TextField("philharmonic:agents.card.reasonPlaceholder", text: $reason, axis: .vertical)
                    .font(.subheadline)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("philharmonic:agents.card.deny") {
                    let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                    answer(.deny(reason: trimmed.isEmpty ? nil : trimmed))
                }
                .buttonStyle(.bordered)
                Button("philharmonic:agents.card.allow") { answer(.allow) }
                    .buttonStyle(.borderedProminent)
            }
            .disabled(sending)
        }
        .padding(12)
        .background(.fill.tertiary, in: .rect(cornerRadius: 14))
    }

    private func answer(_ value: AgentAnswer) {
        sending = true
        Task {
            await model.respond(card: card, prompt: prompt, answer: value)
            sending = false
        }
    }
}

/// A coding agent's questions: each one's choices, free text where it is offered, then Answer.
private struct QuestionPromptView: View {
    let card: AgentCard
    let prompt: AgentPrompt
    let questions: [AgentQuestion]
    let model: GroupChatViewModel

    @State private var picked: [String: [String]] = [:]
    @State private var other: [String: String] = [:]
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(questions, id: \.answerKey) { question in
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: question.question)
                        .font(.subheadline.weight(.medium))
                    ForEach(question.options, id: \.label) { option in
                        choice(option, in: question)
                    }
                    if AgentPromptForm.offersFreeText(question) {
                        freeText(for: question)
                    }
                }
            }
            HStack {
                Spacer()
                Button("philharmonic:agents.card.submit") {
                    sending = true
                    let answer = AgentPromptForm.answer(for: questions, picked: picked, other: other)
                    Task {
                        await model.respond(card: card, prompt: prompt, answer: answer)
                        sending = false
                        // A secret lives here only, and not a moment past its send.
                        for question in questions where question.isSecret == true { other[question.answerKey] = nil }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(sending || !AgentPromptForm.isComplete(questions, picked: picked, other: other))
            }
        }
        .padding(12)
        .background(.fill.tertiary, in: .rect(cornerRadius: 14))
    }

    private func choice(_ option: AgentQuestion.Option, in question: AgentQuestion) -> some View {
        let key = question.answerKey
        let checked = picked[key, default: []].contains(option.label)
        let symbol = Self.symbol(multiSelect: question.multiSelect, checked: checked)
        return Button {
            picked[key] = AgentPromptForm.toggled(picked[key, default: []], option.label, in: question)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(checked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: option.label)
                    if let description = option.description {
                        Text(verbatim: description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }

    /// A box for "pick any", a dot for "pick one".
    private static func symbol(multiSelect: Bool, checked: Bool) -> String {
        switch (multiSelect, checked) {
        case (true, true): "checkmark.square.fill"
        case (true, false): "square"
        case (false, true): "largecircle.fill.circle"
        case (false, false): "circle"
        }
    }

    @ViewBuilder private func freeText(for question: AgentQuestion) -> some View {
        let binding = Binding(get: { other[question.answerKey] ?? "" }, set: { other[question.answerKey] = $0 })
        if question.isSecret == true {
            SecureField("philharmonic:agents.card.secretPlaceholder", text: binding)
                .textFieldStyle(.roundedBorder)
        } else if question.options.isEmpty {
            TextField(text: binding, axis: .vertical) { EmptyView() }
                .textFieldStyle(.roundedBorder)
        } else {
            TextField("philharmonic:agents.card.other", text: binding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
    }
}
