import Models

/// What a member is doing now.
public enum BusyLabel: Sendable, Equatable {
    case orchestrating
    case thinking
    case running(String)
}

/// The desktop's `busy-reducer.ts`: the stream turned into who is doing what right now.
public struct BusyAgents: Sendable, Equatable {
    /// The PM's key, beside the employees' agent ids.
    public static let pm = "__pm__"

    private var busy: [String: BusyLabel] = [:]
    /// messageId → actor, so a tool card is put on the one who called it.
    private var messageActor: [String: String] = [:]

    public init() {}

    public var isEmpty: Bool { busy.isEmpty && messageActor.isEmpty }

    /// `actor`: `BusyAgents.pm` or an employee's agent id.
    public func label(for actor: String) -> BusyLabel? { busy[actor] }

    public mutating func apply(_ event: PhilharmonicSseEvent) {
        switch event {
        case .pmStarted:
            busy[Self.pm] = .orchestrating
        case .pmEnded:
            busy[Self.pm] = nil
        case .messageStart(_, let messageId, let role, let agentId):
            guard let actor = Self.actor(role: role, agentId: agentId) else { return }
            messageActor[messageId] = actor
            busy[actor] = role == .pm ? .orchestrating : .thinking
        case .messageEnd(_, let messageId):
            guard let actor = messageActor.removeValue(forKey: messageId) else { return }
            // The PM stays busy until pm_ended (a turn can send several messages); an employee until its last one.
            if actor != Self.pm, !messageActor.values.contains(actor) { busy[actor] = nil }
        case .toolCard(_, let messageId, let toolName, let phase, _):
            guard let actor = messageActor[messageId] else { return }
            busy[actor] = phase == .start ? .running(toolName) : (actor == Self.pm ? .orchestrating : .thinking)
        case .conversationError:
            busy = [:]
            messageActor = [:]
        default:
            break
        }
    }

    private static func actor(role: GroupRole, agentId: String?) -> String? {
        switch role {
        case .pm: pm
        case .employee: agentId
        default: nil
        }
    }
}
