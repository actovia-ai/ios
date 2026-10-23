import Foundation

/// Who wrote a group message.
public enum GroupRole: Sendable, Equatable, Hashable, Codable {
    case user, pm, employee, system
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "user": self = .user
        case "pm": self = .pm
        case "employee": self = .employee
        case "system": self = .system
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .user: "user"
        case .pm: "pm"
        case .employee: "employee"
        case .system: "system"
        case .unknown(let raw): raw
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// A group (a Philharmonic conversation), as `GET /api/v1/philharmonic/conversations` lists it.
public struct GroupConversation: Codable, Sendable, Equatable, Identifiable, Hashable {
    public struct LatestMessage: Codable, Sendable, Equatable, Hashable {
        public let role: GroupRole
        public let content: String
        public let agentId: String?
        public let createdAt: String

        public init(role: GroupRole, content: String, agentId: String?, createdAt: String) {
            self.role = role
            self.content = content
            self.agentId = agentId
            self.createdAt = createdAt
        }
    }

    public let id: String
    public var title: String
    public var icon: String?
    public var memberAgentIds: [String]?
    public var archived: Bool?
    public let createdAt: String
    public var updatedAt: String
    public var lastMessageAt: String
    public var latestMessage: LatestMessage?

    public init(
        id: String, title: String, icon: String? = nil, memberAgentIds: [String]? = nil, archived: Bool? = nil,
        createdAt: String, updatedAt: String, lastMessageAt: String, latestMessage: LatestMessage? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.memberAgentIds = memberAgentIds
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMessageAt = lastMessageAt
        self.latestMessage = latestMessage
    }
}
