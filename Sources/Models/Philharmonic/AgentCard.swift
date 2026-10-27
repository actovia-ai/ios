import Foundation

/// What an employee message shows for a coding agent's run (Claude Code, Codex); also its stored `parts[0]`.
public struct AgentCard: Decodable, Sendable, Equatable {
    public enum State: String, Sendable, Equatable, WireEnum {
        case working, blocked, done, stopped, error, unknown
        static let unknownCase = State.unknown
        public init(from decoder: Decoder) throws { try self.init(wire: decoder) }
    }

    public struct Step: Decodable, Sendable, Equatable, Identifiable {
        public enum Status: String, Sendable, Equatable, WireEnum {
            case running, ok, error, unknown
            static let unknownCase = Status.unknown
            public init(from decoder: Decoder) throws { try self.init(wire: decoder) }
        }

        /// The CLI's tool_use id.
        public let id: String
        /// As the CLI names it: `Write`, `Bash`.
        public let tool: String
        /// One line: the path, the command, the pattern.
        public let summary: String
        public let status: Status

        public init(id: String, tool: String, summary: String, status: Status) {
            self.id = id
            self.tool = tool
            self.summary = summary
            self.status = status
        }
    }

    public let sessionId: String
    public let agentId: String
    public let runtime: String
    public let model: String?
    public let projectName: String
    public let cwd: String
    public let branch: String?
    public let state: State
    public let steps: [Step]
    /// Finished text blocks of the run, in order.
    public let blocks: [String]
    /// The text block being written now.
    public let pending: String
    public let prompts: [AgentPrompt]
    /// The CLI's notices, verbatim (a rate limit, …).
    public let notices: [String]
    /// Tools the owner denied in this run.
    public let denials: Int
    public let error: String?
    public let continuedInTerminal: Bool
    /// Waiting for a free slot.
    public let queued: Bool

    public init(
        sessionId: String, agentId: String, runtime: String, model: String? = nil, projectName: String, cwd: String,
        branch: String? = nil, state: State, steps: [Step] = [], blocks: [String] = [], pending: String = "",
        prompts: [AgentPrompt] = [], notices: [String] = [], denials: Int = 0,
        error: String? = nil, continuedInTerminal: Bool = false, queued: Bool = false
    ) {
        self.sessionId = sessionId
        self.agentId = agentId
        self.runtime = runtime
        self.model = model
        self.projectName = projectName
        self.cwd = cwd
        self.branch = branch
        self.state = state
        self.steps = steps
        self.blocks = blocks
        self.pending = pending
        self.prompts = prompts
        self.notices = notices
        self.denials = denials
        self.error = error
        self.continuedInTerminal = continuedInTerminal
        self.queued = queued
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId, agentId, runtime, model, projectName, cwd, branch, state, steps, blocks, pending, prompts
        case notices, denials, error, continuedInTerminal, queued
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        agentId = try c.decode(String.self, forKey: .agentId)
        runtime = c.lenient(String.self, forKey: .runtime) ?? ""
        model = c.lenient(String.self, forKey: .model)
        projectName = c.lenient(String.self, forKey: .projectName) ?? ""
        cwd = c.lenient(String.self, forKey: .cwd) ?? ""
        branch = c.lenient(String.self, forKey: .branch)
        state = c.lenient(State.self, forKey: .state) ?? .unknown
        steps = c.lenient([Step].self, forKey: .steps) ?? []
        blocks = c.lenient([String].self, forKey: .blocks) ?? []
        pending = c.lenient(String.self, forKey: .pending) ?? ""
        prompts = c.lenient([AgentPrompt].self, forKey: .prompts) ?? []
        notices = c.lenient([String].self, forKey: .notices) ?? []
        denials = c.lenient(Int.self, forKey: .denials) ?? 0
        error = c.lenient(String.self, forKey: .error)
        continuedInTerminal = c.lenient(Bool.self, forKey: .continuedInTerminal) ?? false
        queued = c.lenient(Bool.self, forKey: .queued) ?? false
    }
}

/// What a blocked run asks the owner.
public enum AgentPrompt: Decodable, Sendable, Equatable {
    /// `summary`: one line for step rows; `detail`: the full command or content being approved.
    case permission(requestId: String, tool: String, summary: String, detail: String)
    case question(requestId: String, questions: [AgentQuestion])
    case unknown(kind: String)

    public var requestId: String? {
        switch self {
        case .permission(let id, _, _, _), .question(let id, _): id
        case .unknown: nil
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, requestId, tool, summary, detail, questions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = c.lenient(String.self, forKey: .kind) ?? ""
        switch kind {
        case "permission":
            self = .permission(
                requestId: try c.decode(String.self, forKey: .requestId),
                tool: c.lenient(String.self, forKey: .tool) ?? "",
                summary: c.lenient(String.self, forKey: .summary) ?? "",
                detail: c.lenient(String.self, forKey: .detail) ?? "")
        case "question":
            self = .question(
                requestId: try c.decode(String.self, forKey: .requestId),
                questions: c.lenient([AgentQuestion].self, forKey: .questions) ?? [])
        default:
            self = .unknown(kind: kind)
        }
    }
}

public struct AgentQuestion: Decodable, Sendable, Equatable {
    public struct Option: Decodable, Sendable, Equatable {
        public let label: String
        public let description: String?

        public init(label: String, description: String? = nil) {
            self.label = label
            self.description = description
        }
    }

    /// Codex keys answers by id; Claude Code leaves it unset (answers keyed by the question's text).
    public let id: String?
    /// Free text is offered as an extra choice.
    public let isOther: Bool?
    /// The answer is a secret: never kept anywhere.
    public let isSecret: Bool?
    public let question: String
    public let header: String?
    public let multiSelect: Bool
    public let options: [Option]

    public init(
        id: String? = nil, isOther: Bool? = nil, isSecret: Bool? = nil, question: String, header: String? = nil,
        multiSelect: Bool = false, options: [Option] = []
    ) {
        self.id = id
        self.isOther = isOther
        self.isSecret = isSecret
        self.question = question
        self.header = header
        self.multiSelect = multiSelect
        self.options = options
    }

    /// The key its answer goes under.
    public var answerKey: String { id ?? question }

    private enum CodingKeys: String, CodingKey { case id, isOther, isSecret, question, header, multiSelect, options }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, forKey: .id)
        isOther = c.lenient(Bool.self, forKey: .isOther)
        isSecret = c.lenient(Bool.self, forKey: .isSecret)
        question = try c.decode(String.self, forKey: .question)
        header = c.lenient(String.self, forKey: .header)
        multiSelect = c.lenient(Bool.self, forKey: .multiSelect) ?? false
        options = c.lenient([Option].self, forKey: .options) ?? []
    }
}

/// The owner's answer to a prompt (`POST /api/v1/agents/sessions/:id/respond`, beside `requestId`).
public enum AgentAnswer: Encodable, Sendable, Equatable {
    public enum Value: Encodable, Sendable, Equatable {
        case one(String)
        case many([String])

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .one(let value): try c.encode(value)
            case .many(let values): try c.encode(values)
            }
        }
    }

    case allow
    case deny(reason: String?)
    /// Keyed by `AgentQuestion.answerKey`.
    case answers([String: Value])

    private enum CodingKeys: String, CodingKey { case kind, reason, answers }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allow:
            try c.encode("allow", forKey: .kind)
        case .deny(let reason):
            try c.encode("deny", forKey: .kind)
            try c.encodeIfPresent(reason, forKey: .reason)
        case .answers(let answers):
            try c.encode("answers", forKey: .kind)
            try c.encode(answers, forKey: .answers)
        }
    }
}
