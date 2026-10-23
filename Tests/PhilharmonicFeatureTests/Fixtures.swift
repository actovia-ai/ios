import Models

@testable import PhilharmonicFeature

/// The desktop tests' builders (merge-group-messages.test.ts and friends), in Swift.
enum Fx {
    static func card(
        sessionId: String = "s1", state: AgentCard.State = .working, queued: Bool = false,
        prompts: [AgentPrompt] = []
    ) -> AgentCard {
        AgentCard(
            sessionId: sessionId, agentId: "a1", runtime: "claude-code", projectName: "Atlas", cwd: "/tmp/atlas",
            state: state, prompts: prompts, queued: queued)
    }

    static func row(
        _ id: String, card: AgentCard? = nil, role: GroupRole = .employee, content: String = "[Claude Code · working]",
        parts: [GroupMessagePart]? = nil, createdAt: String = "2026-10-09T10:00:00.000Z"
    ) -> GroupMessage {
        GroupMessage(
            id: id, conversationId: "c", role: role, agentId: "a1", content: content,
            parts: parts ?? card.map { [.agentCard($0)] } ?? [], taskId: "t", createdAt: createdAt)
    }

    static func live(_ id: String, card: AgentCard? = nil, text: String = "", toolRows: [ToolRow] = []) -> LiveBubble {
        LiveBubble(messageId: id, role: .employee, agentId: "a1", text: text, toolRows: toolRows, agentCard: card)
    }

    static let prompt = AgentPrompt.permission(requestId: "r1", tool: "Bash", summary: "npm install", detail: "npm install")
}
