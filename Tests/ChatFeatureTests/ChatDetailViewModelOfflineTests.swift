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
        // An interactive answer (questionnaire / confirmation) is a write too.
        #expect(vm.canAnswer == false)
        let sent = await vm.sendText("yes")
        #expect(sent == false)
        #expect(recorder.requests == before)
        #expect(vm.messages.map(\.id) == ["u1", "a1"])
        #expect(vm.composerText == "hello again")
        status.markOnline()
        #expect(vm.canSend)
        #expect(vm.canAnswer)
    }

    @Test func refreshAfterReconnectKeepsOlderRuns() async throws {
        func row(_ id: String, _ role: String, _ text: String, _ at: String) -> String {
            role == "user"
                ? #"{"id":"\#(id)","chatId":"c1","role":"user","content":"\#(text)","searchText":"\#(text)","createdAt":"\#(at)"}"#
                : #"{"id":"\#(id)","chatId":"c1","role":"assistant","content":[{"type":"text","text":"\#(text)"}],"usage":{"input":3},"api":"anthropic-messages","provider":"anthropic","model":"claude-x","stopReason":"stop","createdAt":"\#(at)"}"#
        }
        let u1 = row("u1", "user", "one", "2026-09-18T12:00:00.000Z")
        let a1 = row("a1", "assistant", "uno", "2026-09-18T12:00:05.000Z")
        let u2 = row("u2", "user", "two", "2026-09-19T12:00:00.000Z")
        let a2 = row("a2", "assistant", "dos", "2026-09-19T12:00:05.000Z")
        let u3 = row("u3", "user", "three", "2026-09-20T12:00:00.000Z")
        let a3 = row("a3", "assistant", "tres", "2026-09-20T12:00:05.000Z")
        let vm = make(store: makeStore(), status: ConnectionStatus())
        serve(
            rows: ChatPageFixture.page("[\(u2),\(a2)]", hasOlder: true, olderCursor: "cur-newest"), recorder: Recorder())
        await vm.loadHistory()
        serve(
            rows: ChatPageFixture.page("[\(u1),\(a1)]", hasOlder: true, olderCursor: "cur-older"), recorder: Recorder())
        await vm.loadOlder()
        #expect(vm.messages.map(\.id) == ["u1", "a1", "u2", "a2"])
        #expect(vm.olderCursor == "cur-older")

        serve(
            rows: ChatPageFixture.page("[\(u2),\(a2),\(u3),\(a3)]", hasOlder: true, olderCursor: "cur-newest"),
            recorder: Recorder())
        await vm.refreshAfterReconnect()
        #expect(vm.messages.map(\.id) == ["u1", "a1", "u2", "a2", "u3", "a3"])
        #expect(vm.olderCursor == "cur-older")
        #expect(vm.hasOlder)
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
        // Once the turn is over, the same call does fetch: the guard above is what held it back, not a no-op.
        await vm.refreshAfterReconnect()
        #expect(recorder.requests.last == "GET /api/v1/chat/\(chatId)/page")
        #expect(recorder.requests.count == before.count + 1)
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
