import Foundation
import Models

/// One line of a PM round's decision trail, as the disclosure draws it.
public enum RoundLine: Sendable, Equatable {
    public struct Report: Sendable, Equatable {
        public let messageId: String
        public let agentId: String?
        public let name: String

        public init(messageId: String, agentId: String?, name: String) {
            self.messageId = messageId
            self.agentId = agentId
            self.name = name
        }
    }

    case trigger(scheduled: Bool, text: String)
    case reports([Report])
    case thinking(String)
    case text(String)
    case call(tool: String, args: [String: JSONValue], result: String?, isError: Bool, refused: Bool)
    case usage(inputTokens: Int, outputTokens: Int, costUsd: Double)
    case error(message: String, aborted: Bool)

    /// A call the coordinator turned away.
    public var isRefusedCall: Bool {
        if case .call(_, _, _, _, let refused) = self { return refused }
        return false
    }
}

/// The desktop's `lib/pm-round.ts`.
public enum RoundDescription {
    /// Each call paired with its result; a trailing text equal to the bubble's own left out.
    public static func lines(_ events: [PmRoundEvent], bubbleText: String) -> [RoundLine] {
        var results: [String: (text: String, isError: Bool)] = [:]
        for event in events where event.kind == "tool_result" {
            let p = object(event.payload)
            results[string(p["toolCallId"])] = (string(p["text"]), p["isError"] == .bool(true))
        }
        var lines: [RoundLine] = []
        for event in events {
            let p = object(event.payload)
            switch event.kind {
            case "input":
                lines.append(.trigger(scheduled: p["trigger"] == .string("scheduled"), text: string(p["text"])))
            case "reports":
                guard case .array(let messages)? = p["messages"] else {
                    lines.append(.reports([]))
                    continue
                }
                lines.append(
                    .reports(
                        messages.map { m in
                            let m = object(m)
                            let agentId: String? = if case .string(let id)? = m["agentId"] { id } else { nil }
                            return .init(messageId: string(m["messageId"]), agentId: agentId, name: string(m["name"]))
                        }))
            case "thinking":
                lines.append(.thinking(string(p["text"])))
            case "text":
                lines.append(.text(string(p["text"])))
            case "tool_call":
                let tool = string(p["name"])
                let r = results[string(p["toolCallId"])]
                lines.append(
                    .call(
                        tool: tool, args: object(p["args"] ?? .null), result: r?.text, isError: r?.isError ?? false,
                        refused: isRefused(tool: tool, result: r?.text)))
            case "usage":
                // What the model read, the cached part included.
                lines.append(
                    .usage(
                        inputTokens: number(p["inputTokens"]) + number(p["cacheReadTokens"])
                            + number(p["cacheWriteTokens"]),
                        outputTokens: number(p["outputTokens"]), costUsd: double(p["costUsd"])))
            case "error":
                lines.append(.error(message: string(p["message"]), aborted: p["aborted"] == .bool(true)))
            default:
                break
            }
        }
        // The bubble already shows the round's final words.
        if let index = lines.lastIndex(where: { if case .text = $0 { true } else { false } }),
            case .text(let text) = lines[index],
            text.trimmingCharacters(in: .whitespacesAndNewlines) == bubbleText.trimmingCharacters(in: .whitespacesAndNewlines)
        {
            lines.remove(at: index)
        }
        return lines
    }

    /// Why a `waitForQuota` was refused: its result after "Refused: ".
    public static func waitRefusalReason(_ result: String?) -> String {
        guard let result else { return "" }
        guard let range = result.range(of: #"^Refused:?\s*"#, options: .regularExpression) else { return result }
        return String(result[range.upperBound...])
    }

    /// When a scheduled wait wakes the PM: the text after "woken at ", up to the next ".".
    public static func wakeTime(_ result: String?) -> String? {
        guard let result, let start = result.range(of: "woken at ") else { return nil }
        let rest = result[start.upperBound...]
        guard let dot = rest.firstIndex(of: ".") else { return nil }
        let time = rest[..<dot].trimmingCharacters(in: .whitespaces)
        return time.isEmpty ? nil : time
    }

    private static func isRefused(tool: String, result: String?) -> Bool {
        guard let result else { return false }
        return (tool == "delegateTask" && result.hasPrefix("Not started:"))
            || (tool == "waitForQuota" && result.hasPrefix("Refused"))
    }

    private static func object(_ value: JSONValue) -> [String: JSONValue] {
        if case .object(let o) = value { return o }
        return [:]
    }

    private static func string(_ value: JSONValue?) -> String {
        if case .string(let s)? = value { return s }
        return ""
    }

    private static func double(_ value: JSONValue?) -> Double {
        if case .number(let n)? = value { return n }
        return 0
    }

    private static func number(_ value: JSONValue?) -> Int { Int(double(value)) }
}
