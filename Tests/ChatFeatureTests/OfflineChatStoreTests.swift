import Foundation
import Models
import Testing

@testable import ChatFeature

@MainActor @Suite("OfflineChatStore: the per-computer on-disk copy of chats", .serialized)
struct OfflineChatStoreTests {
    private let t = Date(timeIntervalSince1970: 1_800_000_000)

    private func root() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }

    private func store(_ root: URL, _ fingerprint: String = "A") -> OfflineChatStore {
        OfflineChatStore(root: root, fingerprint: fingerprint)
    }

    private func fixturePage() throws -> ChatHistoryPage {
        let rows = #"[{"id":"u1","runId":"u1","role":"user","content":"hi","timestamp":1},{"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"hello"}],"timestamp":2}]"#
        let json = ChatPageFixture.page(rows, hasOlder: true, olderCursor: "u0")
        return try JSONDecoder().decode(ChatHistoryPage.self, from: Data(json.utf8))
    }

    private func chats(_ n: Int) -> [ChatSummary] {
        (0..<n).map { ChatSummary(id: UUID().uuidString, title: "c\($0)", createdAt: "2026-10-0\($0 % 9 + 1)") }
    }

    @Test func roundTripsList() {
        let store = store(root())
        let chats = chats(3)
        let favs = [chats[0]]
        store.saveList(chats: chats, favorites: favs, at: t)
        let loaded = store.loadList()
        #expect(loaded != nil)
        #expect(loaded?.chats == chats && loaded?.favorites == favs && loaded?.savedAt == t)
    }

    @Test func roundTripsPage() throws {
        let store = store(root())
        let fixture = try fixturePage()
        let id = UUID().uuidString
        store.savePage(fixture, chatId: id, at: t)
        let loaded = try #require(store.loadPage(chatId: id))
        #expect(loaded.page.messages.count == fixture.messages.count && loaded.page.olderCursor == fixture.olderCursor)
        #expect(loaded.page.hasOlder == true && loaded.savedAt == t)
    }

    @Test func evictsOldestBeyondFifty() throws {
        let store = store(root())
        let page = try fixturePage()
        let ids = (0..<51).map { _ in UUID().uuidString }
        for (i, id) in ids.enumerated() { store.savePage(page, chatId: id, at: t.addingTimeInterval(Double(i))) }
        let cached = store.cachedChatIds()
        #expect(cached.count == 50 && !cached.contains(ids[0]) && cached.contains(ids[50]))
    }

    @Test func corruptFileReadsAsNil() throws {
        let store = store(root())
        let id = UUID().uuidString
        store.saveList(chats: [], favorites: [], at: t)
        store.savePage(try fixturePage(), chatId: id, at: t)
        let pageFile = store.chatsFolder.appending(path: "\(id).json")
        try Data("{".utf8).write(to: store.listURL)
        try Data("{".utf8).write(to: pageFile)
        #expect(store.loadList() == nil && store.loadPage(chatId: id) == nil)

        try Data(#"{"version":2,"savedAt":"2026-10-28T00:00:00Z","chats":[],"favorites":[]}"#.utf8).write(to: store.listURL)
        try Data(
            #"{"version":2,"savedAt":"2026-10-28T00:00:00Z","page":{"messages":[],"sources":[],"hasOlder":false}}"#.utf8
        ).write(to: pageFile)
        #expect(store.loadList() == nil && store.loadPage(chatId: id) == nil)
    }

    @Test func rejectsNonUUIDChatId() throws {
        let base = root()
        let store = store(base)
        store.savePage(try fixturePage(), chatId: "../x", at: t)
        #expect(store.loadPage(chatId: "../x") == nil)
        #expect(store.cachedChatIds().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.folder.appending(path: "x.json").path(percentEncoded: false)))
    }

    @Test func separatesComputers() {
        let base = root()
        store(base, "A").saveList(chats: chats(1), favorites: [], at: t)
        #expect(store(base, "A").loadList() != nil)
        #expect(store(base, "B").loadList() == nil)
    }

    @Test func pruneKeepsPairedComputers() {
        let base = root()
        store(base, "A").saveList(chats: chats(1), favorites: [], at: t)
        store(base, "B").saveList(chats: chats(1), favorites: [], at: t)
        OfflineChatStore.prune(root: base, keeping: ["A"])
        #expect(store(base, "A").loadList() != nil)
        #expect(!FileManager.default.fileExists(atPath: store(base, "B").folder.path(percentEncoded: false)))
    }

    @Test func clearRemovesEverything() throws {
        let store = store(root())
        store.saveList(chats: chats(1), favorites: [], at: t)
        store.savePage(try fixturePage(), chatId: UUID().uuidString, at: t)
        store.clear()
        #expect(store.loadList() == nil && store.cachedChatIds().isEmpty)
    }

    @Test func evictionOrdersByFileDateWithoutDecoding() throws {
        let store = store(root())
        let ids = (0..<50).map { _ in UUID().uuidString }
        // Fifty files that are not decodable, dated an hour apart; the 51st page is saved over them.
        try FileManager.default.createDirectory(at: store.chatsFolder, withIntermediateDirectories: true)
        for (i, id) in ids.enumerated() {
            let url = store.chatsFolder.appending(path: "\(id).json")
            try Data("not json".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.modificationDate: t.addingTimeInterval(Double(i) * 3600)], ofItemAtPath: url.path)
        }
        let newest = UUID().uuidString
        store.savePage(try fixturePage(), chatId: newest, at: t.addingTimeInterval(100 * 3600))
        let cached = store.cachedChatIds()
        // The oldest by date goes; an undecodable file that is recent enough stays (it was never decoded).
        #expect(cached.count == 50 && !cached.contains(ids[0]) && cached.contains(ids[1]) && cached.contains(newest))
    }
}
