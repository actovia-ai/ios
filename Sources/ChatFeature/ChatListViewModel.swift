import Foundation
import Models
import NetworkingKit
import Observation

@MainActor
@Observable
public final class ChatListViewModel {
    /// The rows loaded so far, newest first — the pages the server handed out, joined.
    public private(set) var chats: [ChatSummary] = []
    /// Every starred chat, from the first page's `favorites`: its own section, whatever the paging.
    public private(set) var favorites: [ChatSummary] = []
    public private(set) var isLoading = false
    /// True while the next page is on its way (`loadMore()`).
    public private(set) var isLoadingMore = false
    /// Where the next page starts; nil once the server said there is nothing older.
    private var olderCursor: String?
    /// Whether an older page can still be asked for.
    public var hasMore: Bool { olderCursor != nil }
    /// How many rows a page carries — a drawer's worth, so a remote phone is not made to wait for years of chats.
    public static let pageSize = 30
    /// True when the last load failed — lets the view tell "couldn't load" from "no chats yet".
    public private(set) var loadFailed = false
    public var errorMessage: String?
    /// True once a load has FINISHED, with a result or a failure (a cancelled load does not count).
    /// Before that the empty list is "not known yet", which the view must not present as "No chats yet".
    public private(set) var hasLoaded = false

    /// Whether the view should raise its "Error" alert. When the list is empty because the load
    /// failed, the "Can't load chats" empty state already shows `errorMessage`, so an alert
    /// would only say the same thing again. The alert stays for a failed delete and for a failed
    /// reload while chats are on screen.
    public var showsErrorAlert: Bool { errorMessage != nil && !(chats.isEmpty && loadFailed) }

    /// When the rows on screen were last read from the computer (or, with `showsCached`, when the stored copy was).
    public private(set) var lastSyncedAt: Date?
    /// True while the list shown is the stored copy, because the computer did not answer.
    public private(set) var showsCached = false
    /// Whether the app may change anything on the computer: not while it does not answer.
    public var canEdit: Bool { !status.isOffline }

    private let apiClient: APIClient
    private let offlineStore: OfflineChatStore?
    private let status: ConnectionStatus
    /// Chats whose DELETE succeeded. A load that started before the delete can finish after it
    /// with a list that still contains the chat; filtering here keeps it from coming back.
    private var deletedIDs: Set<String> = []

    public init(
        apiClient: APIClient, offlineStore: OfflineChatStore? = nil, status: ConnectionStatus = .shared
    ) {
        self.apiClient = apiClient
        self.offlineStore = offlineStore
        self.status = status
    }

    /// Whether a chat can be opened right now: always while the computer answers, else only if its page is stored.
    public func isAvailableOffline(_ chatId: String) -> Bool {
        !status.isOffline || (offlineStore?.cachedChatIds().contains(chatId) ?? false)
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await fetchPage(before: nil)
            apply(firstPage: page)
            loadFailed = false
            hasLoaded = true
        } catch {
            // SwiftUI cancels a view's `.task` when the view goes away; that is not a failure.
            guard !isCancellation(error) else { return }
            if isUnreachable(error) {
                // The computer did not answer: a list already on screen stays; with none, the stored copy is shown.
                if !chats.isEmpty { hasLoaded = true; return }
                if let cached = offlineStore?.loadList() {
                    chats = cached.chats.filter { !deletedIDs.contains($0.id) }
                    favorites = cached.favorites.filter { !deletedIDs.contains($0.id) }
                    olderCursor = nil
                    lastSyncedAt = cached.savedAt
                    showsCached = true
                    loadFailed = false
                    hasLoaded = true
                    return
                }
            }
            loadFailed = true
            hasLoaded = true
            errorMessage = error.localizedDescription
        }
    }

    /// Reloads in the background (the drawer opened, Settings closed). While a list is on screen a
    /// failure is dropped: a stale list is still useful, and an alert every time the drawer opens
    /// offline would be noise. With nothing on screen it is a plain `load()`.
    public func refresh() async {
        guard hasLoaded, !chats.isEmpty else {
            await load()
            return
        }
        guard let page = try? await fetchPage(before: nil) else { return }
        apply(firstPage: page)
        loadFailed = false
    }

    /// The same classification `APIClient` uses to mark the computer offline: no response at all.
    private func isUnreachable(_ error: Error) -> Bool {
        if let url = error as? URLError { return url.code != .cancelled }
        if let http = error as? HTTPError { return http.statusCode == 0 }
        return false
    }

    /// Appends the next page when the list's end comes into view. Nothing happens while a load is
    /// in flight or when the server already said there is nothing older; a failure is dropped
    /// silently (the rows on screen are still good, and the end row offers to try again).
    public func loadMore() async {
        guard let cursor = olderCursor, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await fetchPage(before: cursor) else { return }
        let known = Set(chats.map(\.id))
        chats += page.chats.filter { !known.contains($0.id) && !deletedIDs.contains($0.id) }
        olderCursor = page.olderCursor
    }

    /// The rows for the Recents section: what was loaded, minus the favourites, which have their own.
    public var recents: [ChatSummary] { chats.filter { $0.favorite != true } }

    /// Stars or unstars a chat: the row moves between the sections at once, and comes back if the
    /// server refused. True only when the server confirmed it.
    @discardableResult
    public func toggleFavorite(_ chat: ChatSummary) async -> Bool {
        guard canEdit else { return false }
        let starred = chat.favorite != true
        setFavorite(chat.id, starred)
        do {
            try await apiClient.put("/api/v1/chat", body: FavoriteChatPayload(id: chat.id, favorite: starred))
            return true
        } catch {
            setFavorite(chat.id, !starred)
            guard !isCancellation(error) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func fetchPage(before cursor: String?) async throws -> ChatListPage {
        var query = [URLQueryItem(name: "limit", value: String(Self.pageSize))]
        if let cursor { query.append(URLQueryItem(name: "before", value: cursor)) }
        let data = try await apiClient.data("/api/v1/history", query: query)
        return try ChatListPage.decode(data)
    }

    private func apply(firstPage page: ChatListPage) {
        chats = page.chats.filter { !deletedIDs.contains($0.id) }
        favorites = (page.favorites ?? []).filter { !deletedIDs.contains($0.id) }
        olderCursor = page.olderCursor
        lastSyncedAt = Date()
        showsCached = false
        // A refresh begun on one computer can finish after a switch to another: its list is not this store's.
        if let store = offlineStore, apiClient.activeFingerprint == store.fingerprint {
            store.saveList(chats: chats, favorites: favorites, at: lastSyncedAt ?? Date())
        }
    }

    private func setFavorite(_ id: String, _ starred: Bool) {
        if let index = chats.firstIndex(where: { $0.id == id }) { chats[index].favorite = starred }
        if starred {
            if !favorites.contains(where: { $0.id == id }), var row = chats.first(where: { $0.id == id }) {
                row.favorite = true
                // Newest first, as the server orders them.
                let at = favorites.firstIndex { $0.createdAt < row.createdAt } ?? favorites.endIndex
                favorites.insert(row, at: at)
            }
        } else {
            favorites.removeAll { $0.id == id }
        }
    }

    /// True only when the server confirmed the delete. The row goes at once, as a star does, and comes back where it
    /// was when the computer refuses: waiting for it left the row on screen with nothing said.
    @discardableResult
    public func delete(_ chat: ChatSummary) async -> Bool {
        guard canEdit else { return false }
        let chatIndex = chats.firstIndex { $0.id == chat.id }
        let favoriteIndex = favorites.firstIndex { $0.id == chat.id }
        let removedChat = chatIndex.map { chats[$0] }
        let removedFavorite = favoriteIndex.map { favorites[$0] }
        deletedIDs.insert(chat.id)
        chats.removeAll { $0.id == chat.id }
        favorites.removeAll { $0.id == chat.id }
        do {
            try await apiClient.delete("/api/v1/chat/\(chat.id)")
            return true
        } catch {
            deletedIDs.remove(chat.id)
            if let chatIndex, let removedChat, !chats.contains(where: { $0.id == chat.id }) {
                chats.insert(removedChat, at: min(chatIndex, chats.endIndex))
            }
            if let favoriteIndex, let removedFavorite, !favorites.contains(where: { $0.id == chat.id }) {
                favorites.insert(removedFavorite, at: min(favoriteIndex, favorites.endIndex))
            }
            guard !isCancellation(error) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// True only when the server confirmed the rename (a blank title never reaches it: it would
    /// leave the row with nothing to show). The row takes the new title at once and gets its old
    /// one back if the computer refuses.
    @discardableResult
    public func rename(_ chat: ChatSummary, to title: String) async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canEdit else { return false }
        let previous = chats.first { $0.id == chat.id }?.title ?? favorites.first { $0.id == chat.id }?.title ?? chat.title
        setTitle(chat.id, trimmed)
        do {
            try await apiClient.put("/api/v1/chat", body: RenameChatPayload(id: chat.id, title: trimmed))
            return true
        } catch {
            setTitle(chat.id, previous)
            guard !isCancellation(error) else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func setTitle(_ id: String, _ title: String) {
        if let index = chats.firstIndex(where: { $0.id == id }) { chats[index].title = title }
        if let index = favorites.firstIndex(where: { $0.id == id }) { favorites[index].title = title }
    }
}

/// The desktop's `PUT /api/v1/chat` takes a partial `Chat` row; sending only `id` and `title`
/// updates just that column (Drizzle's `.set()` writes only the keys it is given).
private struct RenameChatPayload: Encodable {
    let id: String
    let title: String
}

/// Likewise `id` and `favorite` alone star or unstar a chat (the desktop's own sidebar sends the same).
private struct FavoriteChatPayload: Encodable {
    let id: String
    let favorite: Bool
}
