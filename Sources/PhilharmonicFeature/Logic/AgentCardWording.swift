import Foundation
import Models

/// The desktop's `lib/agent-card.ts` and `lib/tool-label.ts`: how a coding agent's card reads.
public enum AgentCardWording {
    /// The CLIs' names, as the desktop's `CLI_NAMES`.
    public static func cliName(_ runtime: String) -> String {
        switch runtime {
        case "claude-code": "Claude Code"
        case "codex": "Codex"
        default: runtime
        }
    }

    /// The last `max` steps, and how many came before them.
    public static func visibleSteps(_ card: AgentCard, max: Int = 6) -> (shown: [AgentCard.Step], hidden: Int) {
        let hidden = Swift.max(0, card.steps.count - max)
        return (Array(card.steps.dropFirst(hidden)), hidden)
    }

    /// The last part of the card's `agents.card.state.*` key.
    public static func stateKey(_ card: AgentCard) -> String {
        if card.queued { return "queued" }
        switch card.state {
        case .working, .unknown: return "working"
        case .blocked: return "waiting"
        case .done: return "done"
        case .stopped: return "stopped"
        case .error: return "failed"
        }
    }

    /// `read_file` → "Read File", `WebFetch` → "Web Fetch"; "Mcp" is written "MCP".
    public static func toolLabel(_ name: String) -> String {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in name {
            if character == "_" || character == "-" || character == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase, let previous, previous.isLowercase || previous.isNumber {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
            previous = character
        }
        if !current.isEmpty { words.append(current) }
        return words.map { word in
            let capital = word.prefix(1).uppercased() + word.dropFirst().lowercased()
            return capital == "Mcp" ? "MCP" : capital
        }.joined(separator: " ")
    }

    /// An MCP tool (`mcp__<server>__<tool>`, a plugin's server `plugin_<plugin>_<server>`) names its server first.
    public static func cliToolLabel(_ tool: String) -> String {
        guard let match = tool.wholeMatch(of: /mcp__(.+?)__(.+)/) else { return toolLabel(tool) }
        var server = String(match.1)
        if server.hasPrefix("plugin_") { server.removeFirst("plugin_".count) }
        if let doubled = server.wholeMatch(of: /(.+)_\1/) { server = String(doubled.1) }
        return "\(toolLabel(server)) · \(toolLabel(String(match.2)))"
    }

    /// A step's summary with the run's folder taken off its paths (display only).
    public static func relativeSummary(_ summary: String, cwd: String) -> String {
        var root = cwd
        while root.hasSuffix("/") { root.removeLast() }
        guard !root.isEmpty else { return summary }
        let escaped = NSRegularExpression.escapedPattern(for: root)
        var result = summary
        result = result.replacingOccurrences(
            of: #"(?<![\w./-])"# + escaped + "/", with: "", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"(?<![\w./-])"# + escaped + #"(?=$|["'\s])"#, with: ".", options: .regularExpression)
        return result
    }
}
