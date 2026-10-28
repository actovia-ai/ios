import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import ChatFeature

private final class OfflineDetailMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var holdsChatPostOpen = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let holdsOpen = Self.holdsChatPostOpen
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let isChatPost = request.httpMethod == "POST" && request.url?.path == "/api/v1/chat"
        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1",
                headerFields: isChatPost ? ["Content-Type": "text/event-stream"] : nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            if !(isChatPost && holdsOpen) { client?.urlProtocolDidFinishLoading(self) }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OfflineDetailMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private final class Recorder: Sendable {
    private let storage = Mutex<[String]>([])
    func record(_ line: String) { storage.withLock { $0.append(line) } }
    var requests: [String] { storage.withLock { $0 } }
}

private let rowsJSON = #"""
    [{"id":"u1","chatId":"c1","role":"user","content":"hi","searchText":"hi","createdAt":"2026-09-18T12:00:00.000Z"},
     {"id":"a1","chatId":"c1","role":"assistant","content":[{"type":"text","text":"hello"}],"usage":{"input":3},"api":"anthropic-messages","provider":"anthropic","model":"claude-x","stopReason":"stop","createdAt":"2026-09-18T12:00:05.000Z"}]
    """#

@MainActor
@Suite("ChatDetailViewModel offline", .serialized)
struct ChatDetailViewModelOfflineTests {
    private let chatId = "6F9619FF-8B86-D011-B42D-00C04FC964FF"
    private let seeded = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() -> OfflineChatStore {
        OfflineChatStore(
            root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory),
            fingerprint: "A")
    }

    private func make(store: OfflineChatStore?, status: ConnectionStatus, _ suite: String = #function)
        -> ChatDetailViewModel
    {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let config = ServerConfigStore(userDefaults: defaults)
        let session = OfflineDetailMockURLProtocol.makeSession()
        let client = APIClient(session: session, serverConfig: config, status: status)
        return ChatDetailViewModel(
            chatId: chatId, apiClient: client, streamManager: ChatStreamManager(sseClient: SSEClient(session: session)),
            serverConfig: config, offlineStore: store, status: status)
    }

    private func serve(
        rows: String = rowsJSON, failure: URLError? = nil, status: Int = 200, holdOpen: Bool = false,
        failChatPost: URLError? = nil, recorder: Recorder
    ) {
        OfflineDetailMockURLProtocol.holdsChatPostOpen = holdOpen
        OfflineDetailMockURLProtocol.handler = { request in
            let method = request.httpMethod ?? "GET"
            let path = request.url?.path ?? ""
            recorder.record("\(method) \(path)")
            if method == "POST", path == "/api/v1/chat", let failChatPost { throw failChatPost }
            if method == "POST", path == "/api/v1/chat" { return (200, Data()) }
            if let failure { throw failure }
            return (status, ChatPageFixture.wrap(Data(rows.utf8), path: path))
        }
    }

    private func cachedPage() throws -> ChatHistoryPage {
        try JSONDecoder().decode(
            ChatHistoryPage.self, from: Data(ChatPageFixture.page(#"[{"id":"k1","chatId":"c1","role":"user","content":"cached question","searchText":"x","createdAt":"2026-09-18T12:00:00.000Z"}]"#).utf8))
    }

    @Test func savesNewestPage() async throws {
        let store = makeStore()
        serve(recorder: Recorder())
        let vm = make(store: store, status: ConnectionStatus())
        await vm.loadHistory()
        let saved = try #require(store.loadPage(chatId: chatId))
        #expect(saved.page.messages.map(\.id) == ["u1", "a1"])
        #expect(vm.showsCached == false)
        #expect(vm.lastSyncedAt != nil)

        // An older page is not written.
        serve(
            rows: #"[{"id":"u0","chatId":"c1","role":"user","content":"old","searchText":"old","createdAt":"2026-09-17T12:00:00.000Z"}]"#,
            recorder: Recorder())
        await vm.loadOlder()
        #expect(try #require(store.loadPage(chatId: chatId)).page.messages.map(\.id) == ["u1", "a1"])
    }

    @Test func fallsBackToCachedPage() async throws {
        let store = makeStore()
        store.savePage(try cachedPage(), chatId: chatId, at: seeded)
        serve(failure: URLError(.notConnectedToInternet), recorder: Recorder())
        let vm = make(store: store, status: ConnectionStatus())
        await vm.loadHistory()
        #expect(vm.messages.map(\.displayText) == ["cached question"])
        #expect(vm.hasLoadedHistory)
        #expect(vm.showsCached)
        #expect(vm.lastSyncedAt == seeded)
        #expect(vm.errorMessage == nil)
        #expect(vm.showsErrorAlert == false)
    }

    @Test func noCachedPageShowsError() async {
        serve(failure: URLError(.notConnectedToInternet), recorder: Recorder())
        let vm = make(store: makeStore(), status: ConnectionStatus())
        await vm.loadHistory()
        #expect(vm.hasLoadedHistory == false)
        #expect(vm.showsCached == false)
        #expect(vm.errorMessage != nil)
        #expect(vm.showsErrorAlert)
    }

    @Test func serverErrorDoesNotFallBack() async throws {
        let store = makeStore()
        store.savePage(try cachedPage(), chatId: chatId, at: seeded)
        serve(rows: #"{"type":"error","error":{"code":"X","message":"boom"}}"#, status: 500, recorder: Recorder())
        let vm = make(store: store, status: ConnectionStatus())
        await vm.loadHistory()
        #expect(vm.showsCached == false)
        #expect(vm.messages.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test func offlineRefusesWrites() async throws {
        let recorder = Recorder()
        serve(recorder: recorder)
        let status = ConnectionStatus()
        let vm = make(store: makeStore(), status: status)
        await vm.loadHistory()
        #expect(vm.canSend == false)  // empty draft
        vm.composerText = "hello again"
        #expect(vm.canSend)
        #expect(vm.canRegenerate)
        status.markOffline()
        #expect(vm.isReadOnly)
        #expect(vm.canSend == false)
        #expect(vm.canRegenerate == false)
        #expect(vm.canChoose == false)
        let before = recorder.requests
        await vm.sendMessage()
        await vm.regenerate()
        await vm.choose(runId: "u1")
        #expect(recorder.requests == before)
        #expect(vm.composerText == "hello again")
        #expect(vm.messages.map(\.id) == ["u1", "a1"])
        status.markOnline()
        #expect(vm.canSend)
    }

    @Test func refreshAfterReconnectKeepsScreenAndWritesStore() async throws {
        let store = makeStore()
        store.savePage(try cachedPage(), chatId: chatId, at: seeded)
        serve(failure: URLError(.timedOut), recorder: Recorder())
        let status = ConnectionStatus()
        let vm = make(store: store, status: status)
        await vm.loadHistory()
        #expect(vm.showsCached)
        let recorder = Recorder()
        serve(recorder: recorder)
        await vm.refreshAfterReconnect()
        #expect(recorder.requests == ["GET /api/v1/chat/\(chatId)/page"])
        #expect(vm.showsCached == false)
        #expect(vm.messages.map(\.id) == ["u1", "a1"])
        #expect(try #require(store.loadPage(chatId: chatId)).page.messages.map(\.id) == ["u1", "a1"])
        #expect(vm.lastSyncedAt != seeded)
    }

    @Test func refreshAfterReconnectWaitsForStream() async throws {
        let recorder = Recorder()
        serve(holdOpen: true, recorder: recorder)
        let vm = make(store: makeStore(), status: ConnectionStatus())
        await vm.loadHistory()
        vm.composerText = "go"
        let sending = Task { await vm.sendMessage() }
        let start = ContinuousClock.now
        while !vm.isTurnInFlight, ContinuousClock.now < start + .seconds(5) { try await Task.sleep(for: .milliseconds(2)) }
        #expect(vm.isTurnInFlight)
        let before = recorder.requests
        await vm.refreshAfterReconnect()
        #expect(recorder.requests == before)
        await vm.stop()
        await sending.value
    }

    @Test func streamTransportFailureMarksOffline() async throws {
        let recorder = Recorder()
        serve(failChatPost: URLError(.networkConnectionLost), recorder: recorder)
        let status = ConnectionStatus()
        let vm = make(store: makeStore(), status: status)
        await vm.loadHistory()
        vm.composerText = "go"
        await vm.sendMessage()
        #expect(status.isOffline)
        #expect(vm.errorMessage != nil)
        #expect(vm.liveRunError != nil)
    }
}
