/// One chat in `GET /api/v1/chat/search`: the server groups the matching messages by chat, orders
/// the chats by `matchedAt` (newest first) and builds the snippets.
public struct ChatSearchResult: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { chatId }
    public var chatId: String
    public var title: String
    /// ISO 8601: the newest matching message's time, or the chat's own when only its title matched.
    public var matchedAt: String
    /// At most 3, newest first; empty when only the title matched.
    public var snippets: [ChatSearchSnippet]

    public init(chatId: String, title: String, matchedAt: String, snippets: [ChatSearchSnippet] = []) {
        self.chatId = chatId
        self.title = title
        self.matchedAt = matchedAt
        self.snippets = snippets
    }
}

/// The context of one matching message: plain text of about 160 characters around the first
/// matched word, with '…' marking a cut.
public struct ChatSearchSnippet: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { messageId }
    public var messageId: String
    public var role: String
    public var text: String
    public var createdAt: String

    public init(messageId: String, role: String, text: String, createdAt: String) {
        self.messageId = messageId
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}
