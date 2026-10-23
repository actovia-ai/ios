import Foundation

/// An event of a group's stream (`GET …/conversations/:id/sse`). Task-scoped events and any type this build does
/// not know are `unknown`, never fatal.
public enum PhilharmonicSseEvent: Decodable, Sendable, Equatable {
    public enum ToolPhase: String, Sendable, Equatable, WireEnum {
        case start, end, unknown
        static let unknownCase = ToolPhase.unknown
        public init(from decoder: Decoder) throws { try self.init(wire: decoder) }
    }

    case messageStart(conversationId: String, messageId: String, role: GroupRole, agentId: String?)
    /// `delta` is the whole text so far: it replaces, never appends.
    case messageDelta(conversationId: String, messageId: String, delta: String)
    case messageEnd(conversationId: String, messageId: String)
    case toolCard(conversationId: String, messageId: String, toolName: String, phase: ToolPhase, result: JSONValue?)
    case agentCard(conversationId: String, messageId: String, card: AgentCard)
    case memberJoined(conversationId: String, agentId: String)
    case roundStart(conversationId: String, label: String)
    case askUser(conversationId: String, question: String, options: [String])
    case conversationError(conversationId: String, error: String)
    case pmStarted(conversationId: String)
    /// `reason`: `done`, `error` or `aborted`.
    case pmEnded(conversationId: String, reason: String)
    case delegationRetry(
        conversationId: String, taskId: String, agentId: String, attempt: Int, delayMs: Int, error: String)
    case planCreated(conversationId: String, plan: GroupPlan)
    case planStepUpdated(conversationId: String, stepId: String, patch: PlanStepPatch)
    case planStepAppended(conversationId: String, step: PlanStep)
    case planStatusChanged(conversationId: String, status: GroupPlan.Status)
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, conversationId, messageId, role, agentId, delta, toolName, phase, result, card, label, question
        case options, error, reason, taskId, attempt, delayMs, plan, stepId, patch, step, status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        func id() throws -> String { try c.decode(String.self, forKey: .conversationId) }
        func string(_ key: CodingKeys) throws -> String { try c.decode(String.self, forKey: key) }
        switch type {
        case "message_start":
            self = .messageStart(
                conversationId: try id(), messageId: try string(.messageId),
                role: try c.decode(GroupRole.self, forKey: .role), agentId: c.lenient(String.self, forKey: .agentId))
        case "message_delta":
            self = .messageDelta(conversationId: try id(), messageId: try string(.messageId), delta: try string(.delta))
        case "message_end":
            self = .messageEnd(conversationId: try id(), messageId: try string(.messageId))
        case "tool_card":
            self = .toolCard(
                conversationId: try id(), messageId: try string(.messageId), toolName: try string(.toolName),
                phase: try c.decode(ToolPhase.self, forKey: .phase), result: c.lenient(JSONValue.self, forKey: .result))
        case "agent_card":
            self = .agentCard(
                conversationId: try id(), messageId: try string(.messageId),
                card: try c.decode(AgentCard.self, forKey: .card))
        case "member_joined":
            self = .memberJoined(conversationId: try id(), agentId: try string(.agentId))
        case "round_start":
            self = .roundStart(conversationId: try id(), label: try string(.label))
        case "ask_user":
            self = .askUser(
                conversationId: try id(), question: try string(.question),
                options: c.lenient([String].self, forKey: .options) ?? [])
        case "conversation_error":
            self = .conversationError(conversationId: try id(), error: try string(.error))
        case "pm_started":
            self = .pmStarted(conversationId: try id())
        case "pm_ended":
            self = .pmEnded(conversationId: try id(), reason: c.lenient(String.self, forKey: .reason) ?? "done")
        case "delegation_retry":
            self = .delegationRetry(
                conversationId: try id(), taskId: try string(.taskId), agentId: try string(.agentId),
                attempt: try c.decode(Int.self, forKey: .attempt), delayMs: try c.decode(Int.self, forKey: .delayMs),
                error: c.lenient(String.self, forKey: .error) ?? "")
        case "plan_created":
            self = .planCreated(conversationId: try id(), plan: try c.decode(GroupPlan.self, forKey: .plan))
        case "plan_step_updated":
            self = .planStepUpdated(
                conversationId: try id(), stepId: try string(.stepId),
                patch: try c.decode(PlanStepPatch.self, forKey: .patch))
        case "plan_step_appended":
            self = .planStepAppended(conversationId: try id(), step: try c.decode(PlanStep.self, forKey: .step))
        case "plan_status_changed":
            self = .planStatusChanged(
                conversationId: try id(), status: try c.decode(GroupPlan.Status.self, forKey: .status))
        default:
            self = .unknown(type: type)
        }
    }
}
