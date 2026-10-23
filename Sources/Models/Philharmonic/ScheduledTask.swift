import Foundation

/// A group's scheduled task: recurring (`cronExpression`) or one-off (`runAt`).
public struct ScheduledTask: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let conversationId: String?
    public let title: String
    public let description: String?
    public let status: String
    public let priority: String
    public let assignedAgentId: String?
    public let cronExpression: String?
    public let runAt: String?
    public let lastRunAt: String?
    public let lastRunStatus: String?
    public let createdAt: String

    public init(
        id: String, conversationId: String? = nil, title: String, description: String? = nil, status: String,
        priority: String = "medium", assignedAgentId: String? = nil, cronExpression: String? = nil,
        runAt: String? = nil, lastRunAt: String? = nil, lastRunStatus: String? = nil, createdAt: String
    ) {
        self.id = id
        self.conversationId = conversationId
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.assignedAgentId = assignedAgentId
        self.cronExpression = cronExpression
        self.runAt = runAt
        self.lastRunAt = lastRunAt
        self.lastRunStatus = lastRunStatus
        self.createdAt = createdAt
    }
}
