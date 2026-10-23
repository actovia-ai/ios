import Foundation

/// A Philharmonic employee (an agent), as the workforce lists it.
public struct Employee: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let description: String?
    public let teamId: String?
    public let avatarSeed: String?
    public let avatarStyle: String?
    public let model: String?
    public let provider: String?
    /// `actovia` (Actovia's own loop), `claude-code` or `codex`.
    public let runtime: String
    public let isActive: Bool?

    public init(
        id: String, name: String, description: String? = nil, teamId: String? = nil, avatarSeed: String? = nil,
        avatarStyle: String? = nil, model: String? = nil, provider: String? = nil, runtime: String = "actovia",
        isActive: Bool? = true
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.teamId = teamId
        self.avatarSeed = avatarSeed
        self.avatarStyle = avatarStyle
        self.model = model
        self.provider = provider
        self.runtime = runtime
        self.isActive = isActive
    }

    /// A coding agent on the computer, not Actovia's own loop.
    public var isCli: Bool { runtime == "claude-code" || runtime == "codex" }
}

public struct Team: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let description: String?
    public let icon: String?

    public init(id: String, name: String, description: String? = nil, icon: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
    }
}
