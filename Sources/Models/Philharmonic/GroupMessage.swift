import Foundation

/// One stored row of a group's transcript (`GET …/conversations/:id/messages`).
public struct GroupMessage: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let conversationId: String
    public let role: GroupRole
    public let agentId: String?
    public let content: String
    /// Absent or null on the wire is no parts.
    public let parts: [GroupMessagePart]
    public let taskId: String?
    /// The PM round this message closed (a PM message, or its error / interrupted note).
    public let roundId: String?
    public let createdAt: String

    public init(
        id: String, conversationId: String, role: GroupRole, agentId: String? = nil, content: String,
        parts: [GroupMessagePart] = [], taskId: String? = nil, roundId: String? = nil, createdAt: String
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.agentId = agentId
        self.content = content
        self.parts = parts
        self.taskId = taskId
        self.roundId = roundId
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, conversationId, role, agentId, content, parts, taskId, roundId, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        conversationId = try c.decode(String.self, forKey: .conversationId)
        role = try c.decode(GroupRole.self, forKey: .role)
        agentId = c.lenient(String.self, forKey: .agentId)
        content = c.lenient(String.self, forKey: .content) ?? ""
        parts = c.lenient([GroupMessagePart].self, forKey: .parts) ?? []
        taskId = c.lenient(String.self, forKey: .taskId)
        roundId = c.lenient(String.self, forKey: .roundId)
        createdAt = try c.decode(String.self, forKey: .createdAt)
    }

    /// The CLI run this message shows, when it is an employee's on a coding agent.
    public var agentCard: AgentCard? {
        for part in parts {
            if case .agentCard(let card) = part { return card }
        }
        return nil
    }
}

/// A piece of a group message beside its text, by `kind`. One this build cannot read is `unknown` and the rest stay.
public enum GroupMessagePart: Decodable, Sendable, Equatable {
    case attachment(name: String, url: String, contentType: String)
    case artifact(artifactId: String, title: String, code: String)
    /// The PM round's counts, for the collapsed "Decision process" line.
    case decision(delegations: Int, waits: Int)
    case agentCard(AgentCard)
    case unknown(kind: String)

    private enum CodingKeys: String, CodingKey {
        case kind, name, url, contentType, artifactId, title, code, delegations, waits
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = c.lenient(String.self, forKey: .kind) ?? ""
        switch kind {
        case "attachment":
            if let name = c.lenient(String.self, forKey: .name), let url = c.lenient(String.self, forKey: .url),
                let contentType = c.lenient(String.self, forKey: .contentType)
            {
                self = .attachment(name: name, url: url, contentType: contentType)
                return
            }
        case "artifact":
            if let id = c.lenient(String.self, forKey: .artifactId), let code = c.lenient(String.self, forKey: .code) {
                self = .artifact(artifactId: id, title: c.lenient(String.self, forKey: .title) ?? "", code: code)
                return
            }
        case "decision":
            self = .decision(
                delegations: c.lenient(Int.self, forKey: .delegations) ?? 0,
                waits: c.lenient(Int.self, forKey: .waits) ?? 0)
            return
        case "agent_card":
            if let card = try? AgentCard(from: decoder) {
                self = .agentCard(card)
                return
            }
        default:
            break
        }
        self = .unknown(kind: kind)
    }
}
