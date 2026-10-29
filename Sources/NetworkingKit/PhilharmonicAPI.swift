import Foundation
import Models

/// A photo sent with a group message: always a `data:image/…` URL, as in Chat.
public struct OutgoingAttachment: Encodable, Sendable, Equatable {
    public let name: String
    public let url: String
    public let contentType: String

    public init(name: String, url: String, contentType: String) {
        self.name = name
        self.url = url
        self.contentType = contentType
    }
}

/// How an answer to a coding agent's prompt landed.
public enum RespondOutcome: Sendable, Equatable {
    case done
    /// Answered elsewhere (the computer, another device) or the run moved on: not an error.
    case gone
}

/// Philharmonic's routes (`/api/v1/philharmonic/*`, and the coding agents' `/api/v1/agents/*`), over the paired
/// connection.
public struct PhilharmonicAPI: Sendable {
    private let client: APIClient
    private let serverConfig: ServerConfigStore
    private static let base = "/api/v1/philharmonic"

    public init(client: APIClient, serverConfig: ServerConfigStore) {
        self.client = client
        self.serverConfig = serverConfig
    }

    /// Where the group stream goes now, and the session to read it with.
    public var route: ServerRoute { serverConfig.route }

    private static func conversation(_ id: String) -> String { "\(base)/conversations/\(id)" }

    // MARK: Groups

    public func conversations() async throws -> [GroupConversation] {
        try await client.get("\(Self.base)/conversations")
    }

    public func createConversation(title: String, icon: String?) async throws -> GroupConversation {
        struct Body: Encodable { let title: String; let icon: String? }
        return try await client.post("\(Self.base)/conversations", body: Body(title: title, icon: icon))
    }

    public func renameConversation(id: String, title: String, icon: String?) async throws -> GroupConversation {
        struct Body: Encodable { let title: String; let icon: String? }
        return try await client.put(Self.conversation(id), body: Body(title: title, icon: icon))
    }

    public func deleteConversation(id: String) async throws {
        try await client.delete(Self.conversation(id))
    }

    // MARK: A group's transcript

    /// `after`: only the rows saved after that one — for the re-read after a `message_end`; a (re)connect reads all.
    public func messages(conversationId: String, after: String? = nil) async throws -> [GroupMessage] {
        try await client.get(
            "\(Self.conversation(conversationId))/messages",
            query: after.map { [URLQueryItem(name: "after", value: $0)] } ?? [])
    }

    public func send(
        conversationId: String, content: String, attachments: [OutgoingAttachment] = []
    ) async throws -> GroupMessage {
        struct Body: Encodable { let content: String; let attachments: [OutgoingAttachment]? }
        return try await client.post(
            "\(Self.conversation(conversationId))/messages",
            body: Body(content: content, attachments: attachments.isEmpty ? nil : attachments))
    }

    /// Stops the PM's round. Whether one was running.
    public func interrupt(conversationId: String) async throws -> Bool {
        struct Empty: Encodable {}
        struct Reply: Decodable { let wasRunning: Bool? }
        let reply: Reply = try await client.post("\(Self.conversation(conversationId))/interrupt", body: Empty())
        return reply.wasRunning ?? false
    }

    /// Answers the PM's question (`ask_user`).
    public func answerAskUser(conversationId: String, response: String) async throws {
        struct Body: Encodable { let response: String }
        try await client.post("\(Self.conversation(conversationId))/respond", body: Body(response: response))
    }

    /// The group's active plan; nil when there is none.
    public func plan(conversationId: String) async throws -> GroupPlan? {
        try await client.get("\(Self.conversation(conversationId))/plan")
    }

    /// A PM round's decision trail, in order.
    public func round(conversationId: String, roundId: String) async throws -> [PmRoundEvent] {
        try await client.get("\(Self.conversation(conversationId))/rounds/\(roundId)")
    }

    // MARK: Dashboard and workforce

    public func upcomingTasks() async throws -> [ScheduledTask] {
        try await client.get("\(Self.base)/tasks/upcoming")
    }

    public func recurringTasks() async throws -> [ScheduledTask] {
        try await client.get("\(Self.base)/tasks/recurring")
    }

    public func cancelTask(id: String) async throws -> ScheduledTask {
        struct Body: Encodable { let status = "cancelled" }
        return try await client.patch("\(Self.base)/tasks/\(id)", body: Body())
    }

    public func employees() async throws -> [Employee] {
        try await client.get("\(Self.base)/agents")
    }

    public func teams() async throws -> [Team] {
        try await client.get("\(Self.base)/teams")
    }

    /// An employee's DiceBear face as a transparent PNG of `size` pixels, drawn by the desktop exactly as it draws it
    /// (`GET /api/v1/philharmonic/avatar`, ISSUE-296). A desktop from before it answers 404.
    public func avatar(seed: String?, style: String?, size: Int) async throws -> Data {
        var query = [URLQueryItem(name: "size", value: String(size))]
        if let seed { query.append(URLQueryItem(name: "seed", value: seed)) }
        if let style { query.append(URLQueryItem(name: "style", value: style)) }
        return try await client.data("\(Self.base)/avatar", query: query)
    }

    // MARK: Coding agents

    /// What each CLI last reported of the owner's quota.
    public func quota() async throws -> [CliQuota] {
        try await client.get("/api/v1/agents/quota")
    }

    /// Answers a blocked run's prompt. `.gone` when it was answered elsewhere; every other failure throws.
    public func respond(sessionId: String, requestId: String, answer: AgentAnswer) async throws -> RespondOutcome {
        struct Body: Encodable { let requestId: String; let answer: AgentAnswer }
        do {
            try await client.post(
                "/api/v1/agents/sessions/\(sessionId)/respond", body: Body(requestId: requestId, answer: answer))
            return .done
        } catch let error as HTTPError where error.statusCode == 409 && error.code == "AGENT_PROMPT_GONE" {
            return .gone
        }
    }

    // MARK: The group stream

    public func streamRequest(conversationId: String) -> URLRequest? {
        Self.streamRequest(conversationId: conversationId, route: route)
    }

    /// The group's events, on the route of the moment (each reconnect asks again: the best address may have moved).
    public func streamEvents(conversationId: String) throws -> AsyncThrowingStream<SSEItem<PhilharmonicSseEvent>, Error> {
        let route = route
        guard let request = Self.streamRequest(conversationId: conversationId, route: route) else {
            throw URLError(.badURL)
        }
        return SSEClient().events(PhilharmonicSseEvent.self, for: request, session: route.session)
    }

    /// The computer answered 423: unlock it from here (Face ID stands in for its PIN), as the chat does.
    public func unlockComputer() async -> Bool {
        await serverConfig.connection?.unlockComputer(route: route) ?? false
    }

    /// `GET …/conversations/:id/sse` on the route's best address. The server pings every 15 s; the reader decides
    /// when silence means a dead connection, so URLSession is told to wait an hour, as the chat's stream is.
    public static func streamRequest(conversationId: String, route: ServerRoute) -> URLRequest? {
        guard let first = route.bases.first, let base = URL(string: first) else { return nil }
        var request = URLRequest(url: base.appendingPathComponent("\(Self.conversation(conversationId))/sse"))
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let authorization = route.authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 3600
        return request
    }
}
