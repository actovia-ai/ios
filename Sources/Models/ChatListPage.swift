import Foundation

/// One page of `GET /api/v1/history?limit=N[&before=cursor]` — the desktop's paged chat list.
/// `olderCursor` is `"<createdAt ISO>|<id>"` of the last row when more exist; `favorites` comes only with the
/// first page (no `before`): every starred chat, newest first, drawn in its own section whatever the paging.
/// A desktop from before paging answers the same route with a bare array; `ChatListPage.decode` accepts both.
public struct ChatListPage: Decodable, Equatable, Sendable {
    public var chats: [ChatSummary]
    public var olderCursor: String?
    public var favorites: [ChatSummary]?

    public init(chats: [ChatSummary], olderCursor: String? = nil, favorites: [ChatSummary]? = nil) {
        self.chats = chats
        self.olderCursor = olderCursor
        self.favorites = favorites
    }

    /// The page, or — from an older desktop that still sends the whole list — all of it as one page with
    /// no cursor and the starred rows picked out as the favourites.
    public static func decode(_ data: Data) throws -> ChatListPage {
        let decoder = JSONDecoder()
        if let page = try? decoder.decode(ChatListPage.self, from: data) { return page }
        let all = try decoder.decode([ChatSummary].self, from: data)
        return ChatListPage(chats: all, olderCursor: nil, favorites: all.filter { $0.favorite == true })
    }
}
