import Models
import SwiftUI

/// Under a PM message: the round's decision trail, collapsed to its counts; opening it reads the round once.
struct DecisionProcessView: View {
    let roundId: String
    let bubbleText: String
    let counts: GroupDecision?
    let roster: GroupRoster
    let model: GroupChatViewModel

    @State private var isOpen = false
    @State private var lines: [RoundLine]?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Text(verbatim: summary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if isOpen {
                Group {
                    if let lines {
                        if lines.isEmpty {
                            Text("philharmonic:chat.decision.unavailable")
                        } else {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                RoundLineView(line: line, roster: roster)
                            }
                        }
                    } else {
                        Text("philharmonic:chat.decision.loading")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(.separator).frame(width: 1) }
                .task(id: roundId) {
                    guard lines == nil else { return }
                    lines = RoundDescription.lines(await model.round(roundId), bubbleText: bubbleText)
                }
            }
        }
    }

    private var summary: String {
        var parts = [String(localized: "philharmonic:chat.decision.toggle", defaultValue: "Decision process")]
        if let delegations = counts?.delegations, delegations > 0 {
            parts.append(
                String(localized: "philharmonic:chat.decision.delegations", defaultValue: "Delegated: \(String(delegations))"))
        }
        if let waits = counts?.waits, waits > 0 {
            parts.append(String(localized: "philharmonic:chat.decision.waits", defaultValue: "Waited: \(String(waits))"))
        }
        return parts.joined(separator: " · ")
    }
}

/// One line of the trail, as the desktop's `RoundLineView` says it.
private struct RoundLineView: View {
    let line: RoundLine
    let roster: GroupRoster

    var body: some View {
        switch line {
        case .trigger(let scheduled, let text):
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if scheduled {
                        Text("philharmonic:chat.decision.triggerScheduled")
                    } else {
                        Text("philharmonic:chat.decision.triggerUser")
                    }
                }
                .foregroundStyle(.primary)
                Text(verbatim: text).lineLimit(3)
            }
        case .reports(let reports):
            VStack(alignment: .leading, spacing: 2) {
                Text("philharmonic:chat.decision.reports")
                Text(verbatim: reports.map(reportName).joined(separator: ", "))
                    .foregroundStyle(.primary)
            }
        case .thinking(let text):
            Folded(label: String(localized: "philharmonic:chat.decision.thinking", defaultValue: "Thinking")) {
                Text(verbatim: text)
            }
        case .text(let text):
            Text(verbatim: text).foregroundStyle(.primary)
        case .call(let tool, let args, let result, let isError, let refused):
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: sentence(tool: tool, args: args, result: result, refused: refused) + failedSuffix(isError))
                    .foregroundStyle(refused || isError ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                if case .string(let instructions)? = args["instructions"], !instructions.isEmpty {
                    Text(verbatim: instructions).lineLimit(4)
                }
                Folded(label: String(localized: "philharmonic:chat.decision.details", defaultValue: "Arguments and result")) {
                    Text(verbatim: [JSONValue.object(args).prettyText, result ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        case .usage(let input, let output, let cost):
            Text(
                String(
                    localized: "philharmonic:chat.decision.usage",
                    defaultValue: "\(input.formatted()) in · \(output.formatted()) out · $\(cost.formatted(.number.precision(.fractionLength(4))))"))
        case .error(let message, let aborted):
            if aborted {
                Text("philharmonic:chat.decision.interrupted")
            } else {
                Text(String(localized: "philharmonic:chat.decision.error", defaultValue: "Stopped: \(message)"))
                    .foregroundStyle(.red)
            }
        }
    }

    private func failedSuffix(_ isError: Bool) -> String {
        isError ? " · " + String(localized: "philharmonic:chat.decision.failed", defaultValue: "failed") : ""
    }

    private func reportName(_ report: RoundLine.Report) -> String {
        if let employee = roster.employee(report.agentId) { return employee.name }
        if !report.name.isEmpty { return report.name }
        return Self.formerEmployee
    }

    private static var formerEmployee: String {
        String(localized: "philharmonic:chat.decision.formerEmployee", defaultValue: "former employee")
    }

    private func employeeName(_ id: String) -> String { roster.employees[id]?.name ?? Self.formerEmployee }

    /// "Name · CLI · model" for a coding-agent CLI, the name alone otherwise.
    private func delegate(_ id: String) -> String {
        guard let agent = roster.employees[id] else { return Self.formerEmployee }
        guard agent.isCli else { return agent.name }
        let model = agent.model ?? String(localized: "philharmonic:chat.decision.cliDefault", defaultValue: "CLI default")
        return [agent.name, AgentCardWording.cliName(agent.runtime), model].joined(separator: " · ")
    }

    private func sentence(tool: String, args: [String: JSONValue], result: String?, refused: Bool) -> String {
        func string(_ key: String) -> String { if case .string(let s)? = args[key] { s } else { "" } }
        switch tool {
        case "delegateTask":
            let id = string("employeeId")
            if refused {
                let name = employeeName(id)
                return String(localized: "philharmonic:chat.decision.refused", defaultValue: "Not started — \(name)'s quota is used up")
            }
            let who = delegate(id)
            return String(localized: "philharmonic:chat.decision.delegate", defaultValue: "Gave a step to \(who)")
        case "waitForQuota":
            if refused {
                let reason = RoundDescription.waitRefusalReason(result)
                return String(localized: "philharmonic:chat.decision.waitRefused", defaultValue: "Didn't wait — \(reason)")
            }
            let name = employeeName(string("employeeId"))
            let reason = string("reason")
            let wait = String(localized: "philharmonic:chat.decision.wait", defaultValue: "Waited for \(name)'s quota — \(reason)")
            guard let time = RoundDescription.wakeTime(result) else { return wait }
            return wait + " · " + String(localized: "philharmonic:chat.decision.wakeAt", defaultValue: "woken at \(time)")
        case "createPlan":
            let count: Int = if case .array(let steps)? = args["steps"] { steps.count } else { 0 }
            return String(localized: "philharmonic:chat.decision.plan", defaultValue: "Planned steps: \(String(count))")
        case "updatePlanStep":
            let status = stepStatus(string("status"))
            return String(localized: "philharmonic:chat.decision.updateStep", defaultValue: "Marked a step \(status)")
        case "appendPlanStep":
            return String(localized: "philharmonic:chat.decision.appendStep", defaultValue: "Added a step")
        case "recruitEmployee":
            let name = string("name").isEmpty ? string("role") : string("name")
            return String(localized: "philharmonic:chat.decision.recruit", defaultValue: "Recruited \(name)")
        case "createReport":
            return String(localized: "philharmonic:chat.decision.report", defaultValue: "Wrote a report")
        case "escalateToUser", "askUser":
            return String(localized: "philharmonic:chat.decision.askUser", defaultValue: "Asked you")
        case "search_knowledge_base":
            return String(localized: "philharmonic:chat.decision.search", defaultValue: "Searched the knowledge base")
        default:
            return String(localized: "philharmonic:chat.decision.otherTool", defaultValue: "Called \(tool)")
        }
    }

    private func stepStatus(_ status: String) -> String {
        switch status {
        case "pending": String(localized: "philharmonic:chat.decision.status.pending", defaultValue: "pending")
        case "running": String(localized: "philharmonic:chat.decision.status.running", defaultValue: "running")
        case "done": String(localized: "philharmonic:chat.decision.status.done", defaultValue: "done")
        case "skipped": String(localized: "philharmonic:chat.decision.status.skipped", defaultValue: "skipped")
        case "failed": String(localized: "philharmonic:chat.decision.status.failed", defaultValue: "failed")
        default: status
        }
    }
}

/// A label that opens what it holds in place.
private struct Folded<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Text(verbatim: label)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if isOpen { content }
        }
    }
}

extension JSONValue {
    /// Indented JSON, for reading.
    var prettyText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
