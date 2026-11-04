import Foundation
import Models

/// One tool call of an Actovia-runtime employee, drawn as a plain row on the live bubble (the event carries no call
/// id or arguments, and saved rows keep none).
public struct ToolRow: Sendable, Equatable {
    public let toolName: String
    public let phase: PhilharmonicSseEvent.ToolPhase
    public let result: JSONValue?

    public init(toolName: String, phase: PhilharmonicSseEvent.ToolPhase, result: JSONValue?) {
        self.toolName = toolName
        self.phase = phase
        self.result = result
    }
}

/// A message being written now, from the stream: shown until its saved row arrives.
public struct LiveBubble: Sendable, Equatable {
    public let messageId: String
    public let role: GroupRole
    public let agentId: String?
    /// The whole text so far.
    public var text: String
    public var toolRows: [ToolRow]
    public var agentCard: AgentCard?

    public init(
        messageId: String, role: GroupRole, agentId: String?, text: String = "", toolRows: [ToolRow] = [],
        agentCard: AgentCard? = nil
    ) {
        self.messageId = messageId
        self.role = role
        self.agentId = agentId
        self.text = text
        self.toolRows = toolRows
        self.agentCard = agentCard
    }
}

public struct GroupArchiveEntry: Sendable, Equatable, Identifiable {
    public let title: String
    public let path: String
    public let directory: Bool
    public var id: String { path }
}

public struct GroupAttachment: Sendable, Equatable {
    public let name: String
    public let url: String
    public let contentType: String
}

public struct ArtifactPart: Sendable, Equatable {
    public let artifactId: String
    public let title: String
    public let code: String

    public init(artifactId: String, title: String, code: String) {
        self.artifactId = artifactId
        self.title = title
        self.code = code
    }
}

/// A PM round's counts, for the collapsed "Decision process" line.
public struct GroupDecision: Sendable, Equatable {
    public let delegations: Int
    public let waits: Int

    public init(delegations: Int, waits: Int) {
        self.delegations = delegations
        self.waits = waits
    }
}

/// The PM's saved question on its bubble (`GroupMessagePart.question`), with its current status.
public struct BubbleQuestion: Sendable, Equatable {
    public let questionId: String
    public let options: [String]
    public let status: GroupQuestionStatus
}

/// One bubble of a group's transcript, saved or live.
public struct GroupBubble: Sendable, Equatable, Identifiable {
    public let id: String
    public let role: GroupRole
    public let agentId: String?
    public let text: String
    public let attachments: [GroupAttachment]
    public let artifacts: [ArtifactPart]
    public let decision: GroupDecision?
    public let agentCard: AgentCard?
    /// A newer card of the same session followed this one.
    public var agentCardSuperseded: Bool
    public let toolRows: [ToolRow]
    public let roundId: String?
    /// Nil for a live bubble: it is "now".
    public let createdAt: String?
    public let isLive: Bool
    /// The PM's question to the owner, when this bubble is one.
    public var question: BubbleQuestion? = nil
    public var archives: [GroupArchiveEntry] = []
}

/// The desktop's `merge-group-messages.ts`: saved rows are the truth; a live bubble shows only while its message is
/// not saved (a coding agent's step saves its row under the live id as it begins, so it never shows twice).
public enum GroupMessageMerge {
    /// `questionStatus`: statuses settled live (`question_settled`) since the rows were read; they win.
    public static func merge(
        history: [GroupMessage], live: [LiveBubble], liveCards: [String: AgentCard],
        questionStatus: [String: GroupQuestionStatus] = [:]
    ) -> [GroupBubble] {
        let saved = Set(history.map(\.id))
        var merged: [GroupBubble] = history.map { row in
            var attachments: [GroupAttachment] = []
            var archives: [GroupArchiveEntry] = []
            var artifacts: [ArtifactPart] = []
            var decision: GroupDecision?
            var card: AgentCard?
            var question: BubbleQuestion?
            for part in row.parts {
                switch part {
                case .attachment(let name, let url, let contentType):
                    attachments.append(GroupAttachment(name: name, url: url, contentType: contentType))
                case .archive(let title, let path, let directory):
                    archives.append(GroupArchiveEntry(title: title, path: path, directory: directory))
                case .artifact(let id, let title, let code):
                    artifacts.append(ArtifactPart(artifactId: id, title: title, code: code))
                case .decision(let delegations, let waits):
                    if decision == nil { decision = GroupDecision(delegations: delegations, waits: waits) }
                case .agentCard(let c):
                    if card == nil { card = c }
                case .question(let questionId, let options, let status):
                    if question == nil {
                        question = BubbleQuestion(
                            questionId: questionId, options: options, status: questionStatus[questionId] ?? status)
                    }
                case .answer, .unknown:
                    break
                }
            }
            var bubble = GroupBubble(
                id: row.id, role: row.role, agentId: row.agentId, text: row.content, attachments: attachments,
                artifacts: artifacts, decision: decision,
                // The live map carries a card's updates after its row was saved, so it wins over the row.
                agentCard: liveCards[row.id] ?? card, agentCardSuperseded: false, toolRows: [], roundId: row.roundId,
                createdAt: row.createdAt, isLive: false)
            bubble.question = question
            bubble.archives = archives
            return bubble
        }
        for bubble in live where !saved.contains(bubble.messageId) {
            merged.append(
                GroupBubble(
                    id: bubble.messageId, role: bubble.role, agentId: bubble.agentId, text: bubble.text,
                    attachments: [], artifacts: bubble.toolRows.compactMap(artifact(of:)), decision: nil,
                    agentCard: liveCards[bubble.messageId] ?? bubble.agentCard, agentCardSuperseded: false,
                    toolRows: bubble.toolRows, roundId: nil, createdAt: nil, isLive: true))
        }
        // Only a session's latest card is current.
        var latest: [String: String] = [:]
        for bubble in merged {
            if let card = bubble.agentCard { latest[card.sessionId] = bubble.id }
        }
        for index in merged.indices {
            if let card = merged[index].agentCard, latest[card.sessionId] != merged[index].id {
                merged[index].agentCardSuperseded = true
            }
        }
        return merged
    }

    /// An ended tool row whose result is an artifact (the PM's `createReport`), shown before its row is saved.
    private static func artifact(of row: ToolRow) -> ArtifactPart? {
        guard row.phase == .end, case .object(let result)? = row.result, result["type"] == .string("artifact"),
            case .string(let id)? = result["artifactId"], case .string(let code)? = result["code"]
        else { return nil }
        let title: String = if case .string(let t)? = result["title"] { t } else { "" }
        return ArtifactPart(artifactId: id, title: title, code: code)
    }
}
