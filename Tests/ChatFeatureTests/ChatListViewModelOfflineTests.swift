import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import ChatFeature

private final class OfflineListMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    /// While true a request is not answered; it waits in `held` until `releaseHeld()`.
    nonisolated(unsafe) static var holds = false
    nonisolated(unsafe) static var held: [OfflineListMockURLProtocol] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    static func releaseHeld() {
        holds = false
        let pending = held
        held = []
        for call in pending { call.answer() }
    }

    override func startLoading() {
        if Self.holds {
            Self.held.append(self)
            return
        }
        answer()
    }

    private func answer() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineListMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class Recorder: Sendable {
    private let storage = Mutex<[String]>([])
    func record(_ line: String) { storage.withLock { $0.append(line) } }
    var requests: [String] { storage.withLock { $0 } }
}

private let pageJSON = #"""
    {"chats":[{"id":"c1","title":"Trip planning","createdAt":"2026-09-18T00:00:00.000Z","favorite":false},
              {"id":"c2","title":"New chat","createdAt":"2026-09-17T00:00:00.000Z","favorite":null}],
     "olderCursor":"c2","favorites":[]}
    """#

private let olderJSON = #"""
    {"chats":[{"id":"c3","title":"Older","createdAt":"2026-09-10T00:00:00.000Z","favorite":false}],"olderCursor":null}
    """#

@MainActor
@Suite("ChatListViewModel offline", .serialized)
struct ChatListViewModelOfflineTests {
    private let seeded = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() -> OfflineChatStore {
        OfflineChatStore(
            root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            fingerprint: "A")
    }

    /// Pairs `fingerprint` as the active computer on `config`, its requests going through `session`.
    private func pair(_ config: ServerConfigStore, session: URLSession, fingerprint: String?) async throws {
        guard let fingerprint else { return }
        let computer = PairedServer(
            hosts: ["10.0.0.2"], port: 63129, fingerprint: fingerprint, name: "Mac", deviceId: "d", token: "T")
        let connection = ServerConnection(
            store: InMemoryCredentialStore(computers: PairedComputers(servers: [computer], activeFingerprint: fingerprint)),
            sessionFactory: { _ in session })
        try await connection.unlock(reason: "test")
        config.connection = connection
    }

    private func make(store: OfflineChatStore?, status: ConnectionStatus, active: String? = "A", _ suite: String = #function)
        async throws -> ChatListViewModel
    {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        let session = OfflineListMockURLProtocol.makeSession()
        try await pair(config, session: session, fingerprint: active)
        let client = APIClient(session: session, serverConfig: config, status: status)
        return ChatListViewModel(apiClient: client, offlineStore: store, status: status)
    }

    private func serve(
        history: String = pageJSON, failure: URLError? = nil, status: Int = 200, recorder: Recorder
    ) {
        OfflineListMockURLProtocol.handler = { request in
            recorder.record("\(request.httpMethod ?? "GET") \(request.url?.path ?? "")")
            if let failure { throw failure }
            return (status, Data(history.utf8))
        }
    }

    private let cachedChats = [
        ChatSummary(id: "k1", title: "Cached one", createdAt: "2026-09-01T00:00:00.000Z"),
        ChatSummary(id: "k2", title: "Cached two", createdAt: "2026-08-01T00:00:00.000Z", favorite: true),
    ]

    @Test func savesFirstPageOnSuccess() async throws {
        let store = makeStore()
        serve(recorder: Recorder())
        let vm = try await make(store: store, status: ConnectionStatus())
        await vm.load()
        #expect(store.loadList()?.chats.map(\.id) == ["c1", "c2"])
        #expect(vm.lastSyncedAt != nil)
        #expect(vm.showsCached == false)

        // loadMore pages are not saved.
        serve(history: olderJSON, recorder: Recorder())
        await vm.loadMore()
        #expect(vm.chats.map(\.id) == ["c1", "c2", "c3"])
        #expect(store.loadList()?.chats.map(\.id) == ["c1", "c2"])
    }

    @Test func fallsBackToCacheWhenUnreachable() async throws {
        let store = makeStore()
        store.saveList(chats: cachedChats, favorites: [cachedChats[1]], at: seeded)
        serve(failure: URLError(.notConnectedToInternet), recorder: Recorder())
        let vm = try await make(store: store, status: ConnectionStatus())
        await vm.load()
        #expect(vm.chats == cachedChats)
        #expect(vm.favorites == [cachedChats[1]])
        #expect(vm.showsCached)
        #expect(vm.loadFailed == false)
        #expect(vm.errorMessage == nil)
        #expect(vm.lastSyncedAt == seeded)
        #expect(vm.hasLoaded)
        #expect(vm.hasMore == false)
    }

    @Test func cachedListShowsBeforeTheFetchAnswers() async throws {
        let store = makeStore()
        store.saveList(chats: cachedChats, favorites: [cachedChats[1]], at: seeded)
        serve(recorder: Recorder())
        let vm = try await make(store: store, status: ConnectionStatus())
        OfflineListMockURLProtocol.holds = true
        let loading = Task { await vm.load() }
        for _ in 0..<500 where OfflineListMockURLProtocol.held.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(OfflineListMockURLProtocol.held.count == 1)  // the request is still pending
        #expect(vm.chats == cachedChats)
        #expect(vm.favorites == [cachedChats[1]])
        #expect(vm.hasLoaded)
        #expect(vm.loadFailed == false)
        #expect(vm.lastSyncedAt == seeded)
        OfflineListMockURLProtocol.releaseHeld()
        await loading.value
        #expect(vm.chats.map(\.id) == ["c1", "c2"])
        #expect(vm.favorites.isEmpty)
        #expect(vm.showsCached == false)
        #expect(vm.lastSyncedAt != seeded)
        #expect(vm.hasMore)
    }

    @Test func cachedListOfAnotherComputerIsNotShownEarly() async throws {
        let store = makeStore()  // computer "A"
        store.saveList(chats: cachedChats, favorites: [], at: seeded)
        serve(recorder: Recorder())
        let vm = try await make(store: store, status: ConnectionStatus(), active: "B")
        OfflineListMockURLProtocol.holds = true
        let loading = Task { await vm.load() }
        for _ in 0..<500 where OfflineListMockURLProtocol.held.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(vm.chats.isEmpty)
        OfflineListMockURLProtocol.releaseHeld()
        await loading.value
    }

    @Test func noCacheStillShowsCantLoad() async throws {
        serve(failure: URLError(.notConnectedToInternet), recorder: Recorder())
        let vm = try await make(store: makeStore(), status: ConnectionStatus())
        await vm.load()
        #expect(vm.loadFailed)
        #expect(vm.showsCached == false)
        #expect(vm.chats.isEmpty)
    }

    @Test func serverErrorDoesNotFallBackToCache() async throws {
        let store = makeStore()
        store.saveList(chats: cachedChats, favorites: [], at: seeded)
        serve(history: #"{"type":"error","error":{"code":"X","message":"boom"}}"#, status: 500, recorder: Recorder())
        let vm = try await make(store: store, status: ConnectionStatus())
        await vm.load()
        #expect(vm.loadFailed)
        #expect(vm.showsCached == false)
        #expect(vm.chats.isEmpty)
    }

    @Test func successAfterCacheClearsShowsCached() async throws {
        let store = makeStore()
        store.saveList(chats: cachedChats, favorites: [], at: seeded)
        serve(failure: URLError(.timedOut), recorder: Recorder())
        let status = ConnectionStatus()
        let vm = try await make(store: store, status: status)
        await vm.load()
        #expect(vm.showsCached)
        serve(recorder: Recorder())
        await vm.refresh()
        #expect(vm.showsCached == false)
        #expect(vm.chats.map(\.id) == ["c1", "c2"])
        #expect(vm.lastSyncedAt != seeded)
    }

    @Test func editsRefusedOffline() async throws {
        let recorder = Recorder()
        serve(recorder: recorder)
        let status = ConnectionStatus()
        let vm = try await make(store: makeStore(), status: status)
        await vm.load()
        let chat = try #require(vm.chats.first)
        status.markOffline()
        #expect(vm.canEdit == false)
        let before = recorder.requests
        #expect(await vm.rename(chat, to: "New") == false)
        #expect(await vm.delete(chat) == false)
        #expect(await vm.toggleFavorite(chat) == false)
        #expect(recorder.requests == before)
        #expect(vm.chats.map(\.id) == ["c1", "c2"])
        #expect(vm.chats.first?.title == "Trip planning")
        #expect(vm.favorites.isEmpty)
        status.markOnline()
        #expect(vm.canEdit)
    }

    @Test func isAvailableOfflineFollowsCache() async throws {
        let store = makeStore()
        let cachedId = UUID().uuidString
        let page = try JSONDecoder().decode(
            ChatHistoryPage.self,
            from: Data(ChatPageFixture.page("[]", hasOlder: false, olderCursor: nil).utf8))
        store.savePage(page, chatId: cachedId, at: seeded)
        let status = ConnectionStatus()
        let vm = try await make(store: store, status: status)
        #expect(vm.isAvailableOffline("other"))  // online: everything is
        status.markOffline()
        #expect(vm.isAvailableOffline(cachedId))
        #expect(vm.isAvailableOffline("other") == false)
    }

    @Test func listFromAnotherComputerIsNotStored() async throws {
        let store = makeStore()  // computer "A"
        serve(recorder: Recorder())
        let vm = try await make(store: store, status: ConnectionStatus(), active: "B")
        await vm.load()
        #expect(vm.hasLoaded)
        #expect(store.loadList() == nil)
    }
}
