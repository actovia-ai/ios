import Foundation

/// The PM's plan for a group's work (`GET …/conversations/:id/plan`).
public struct GroupPlan: Decodable, Sendable, Equatable, Identifiable {
    public enum Status: String, Sendable, Equatable, WireEnum {
        case drafting, active, completed, aborted, unknown
        static let unknownCase = Status.unknown
        public init(from decoder: Decoder) throws { try self.init(wire: decoder) }
    }

    public let id: String
    public let conversationId: String
    public var summary: String
    public var status: Status
    public let createdAt: String
    public var updatedAt: String
    public var steps: [PlanStep]

    public init(
        id: String, conversationId: String, summary: String, status: Status, createdAt: String, updatedAt: String,
        steps: [PlanStep]
    ) {
        self.id = id
        self.conversationId = conversationId
        self.summary = summary
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.steps = steps
    }
}

public struct PlanStep: Decodable, Sendable, Equatable, Identifiable {
    public enum Status: String, Sendable, Equatable, WireEnum {
        case pending, running, done, skipped, failed, unknown
        static let unknownCase = Status.unknown
        public init(from decoder: Decoder) throws { try self.init(wire: decoder) }
    }

    public let id: String
    public let planId: String
    public var ordinal: Int
    public var title: String
    public var intent: String?
    public var assignedAgentId: String?
    public var status: Status
    public var output: String?
    public var note: String?
    public var taskId: String?
    public var startedAt: String?
    public var completedAt: String?

    public init(
        id: String, planId: String, ordinal: Int, title: String, intent: String? = nil,
        assignedAgentId: String? = nil, status: Status, output: String? = nil, note: String? = nil,
        taskId: String? = nil, startedAt: String? = nil, completedAt: String? = nil
    ) {
        self.id = id
        self.planId = planId
        self.ordinal = ordinal
        self.title = title
        self.intent = intent
        self.assignedAgentId = assignedAgentId
        self.status = status
        self.output = output
        self.note = note
        self.taskId = taskId
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

/// `plan_step_updated`'s patch: a field left out keeps the step's value, a null clears it.
public struct PlanStepPatch: Decodable, Sendable, Equatable {
    public var status: Patch<PlanStep.Status>
    public var output: Patch<String>
    public var note: Patch<String>
    public var startedAt: Patch<String>
    public var completedAt: Patch<String>
    public var assignedAgentId: Patch<String>
    public var title: Patch<String>
    public var intent: Patch<String>

    public init(
        status: Patch<PlanStep.Status> = .absent, output: Patch<String> = .absent, note: Patch<String> = .absent,
        startedAt: Patch<String> = .absent, completedAt: Patch<String> = .absent,
        assignedAgentId: Patch<String> = .absent, title: Patch<String> = .absent, intent: Patch<String> = .absent
    ) {
        self.status = status
        self.output = output
        self.note = note
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.assignedAgentId = assignedAgentId
        self.title = title
        self.intent = intent
    }

    private enum CodingKeys: String, CodingKey {
        case status, output, note, startedAt, completedAt, assignedAgentId, title, intent
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.patch(PlanStep.Status.self, forKey: .status)
        output = try c.patch(String.self, forKey: .output)
        note = try c.patch(String.self, forKey: .note)
        startedAt = try c.patch(String.self, forKey: .startedAt)
        completedAt = try c.patch(String.self, forKey: .completedAt)
        assignedAgentId = try c.patch(String.self, forKey: .assignedAgentId)
        title = try c.patch(String.self, forKey: .title)
        intent = try c.patch(String.self, forKey: .intent)
    }
}
