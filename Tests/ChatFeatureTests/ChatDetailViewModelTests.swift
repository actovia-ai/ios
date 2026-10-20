import Foundation
import Models
import NetworkingKit
import Observation
import Synchronization
import Testing

@testable import ChatFeature

private final class ChatDetailMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?
    /// When true, a `POST /api/v1/chat` answer is delivered but the connection is never finished,
    /// i.e. a turn that is still streaming.
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
            if !(isChatPost && holdsOpen) {
                client?.urlProtocolDidFinishLoading(self)
            }
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChatDetailMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private struct RecordedRequest: Sendable {
    let line: String  // "METHOD path"
    let body: Data
}

/// The handler runs on a URLProtocol thread, so requests are recorded behind a lock and asserted afterwards.
private final class RequestRecorder: Sendable {
    private let storage = Mutex<[RecordedRequest]>([])
    func record(_ request: RecordedRequest) { storage.withLock { $0.append(request) } }
    var lines: [String] { storage.withLock { $0.map(\.line) } }

    /// The JSON object of the one and only body sent to `POST path`.
    func onlyJSONBody(forPOST path: String) throws -> [String: Any] {
        let bodies = storage.withLock { $0.filter { $0.line == "POST \(path)" }.map(\.body) }
        try #require(bodies.count == 1)
        let object = try JSONSerialization.jsonObject(with: bodies[0])
        return try #require(object as? [String: Any])
    }
}

private let historyRowsJSON = #"""
    [{"id":"u1","chatId":"c1","role":"user","content":"hi","searchText":"hi","createdAt":"2026-09-18T12:00:00.000Z"},
     {"id":"a1","chatId":"c1","role":"assistant","content":[{"type":"text","text":"hello"}],"usage":{"input":3},"api":"anthropic-messages","provider":"anthropic","model":"claude-x","stopReason":"stop","createdAt":"2026-09-18T12:00:05.000Z"}]
    """#

private let helloReply = """
    data: {"type":"message_update","message":{"id":"a2","role":"assistant","content":"Hel"}}\n\n\
    data: {"type":"message_update","message":{"id":"a2","role":"assistant","content":"Hello!"}}\n\n\
    data: {"type":"title","title":"Greeting"}\n\n\
    data: {"type":"done","messages":[{"id":"u2","role":"user","content":"hey"},{"id":"a2","role":"assistant","content":"Hello!"}]}\n\n
    """

private let partialReply = """
    data: {"type":"message_update","message":{"id":"a2","role":"assistant","content":"Hel"}}\n\n
    """

private let toolResultReply = """
    data: {"type":"message_update","message":{"id":"t1","role":"toolResult","toolName":"search","content":"ok"}}\n\n
    """

private let multilineTitleReply = """
    data: {"type":"title","title":"First line\\n\\nSecond line"}\n\n\
    data: {"type":"done","messages":[{"id":"u2","role":"user","content":"hey"},{"id":"a2","role":"assistant","content":"Hello!"}]}\n\n
    """

/// A chat whose transcript ends with the user's message (for example a turn that failed): nothing
/// is in flight, so there must be no pending row.
private let userOnlyHistoryJSON = #"""
    [{"id":"u1","chatId":"c1","role":"user","content":"hi","searchText":"hi","createdAt":"2026-09-18T12:00:00.000Z"}]
    """#

private let envelope404 = #"{"type":"error","error":{"code":"CHAT_NOT_FOUND","message":"Chat not found"}}"#

/// Answers `GET /api/v1/chat/<id>` with `history` and `POST /api/v1/chat` with `reply`, recording every request.
private func serve(
    history: String = "[]",
    historyStatus: Int = 200,
    reply: String = "",
    replyStatus: Int = 200,
    holdReplyOpen: Bool = false,
    recorder: RequestRecorder
) {
    ChatDetailMockURLProtocol.holdsChatPostOpen = holdReplyOpen
    ChatDetailMockURLProtocol.handler = { request in
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let body = method == "POST" ? try request.httpBodyStreamData() : Data()
        recorder.record(RecordedRequest(line: "\(method) \(path)", body: body))
        if method == "GET", path.hasPrefix("/api/v1/chat/") {
            return (historyStatus, ChatPageFixture.wrap(Data(history.utf8), path: path))
        }
        if method == "POST", path == "/api/v1/chat" { return (replyStatus, Data(reply.utf8)) }
        return (404, Data(envelope404.utf8))
    }
}

extension URLRequest {
    fileprivate func httpBodyStreamData() throws -> Data {
        guard let stream = httpBodyStream else { return httpBody ?? Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Polls (bounded) until `condition` holds — no timing assumption, just a deadline so a broken build fails instead of hanging.
@MainActor
private func waitUntil(
    _ what: String, timeout: Duration = .seconds(10), _ condition: @MainActor () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !(await condition()) {
        try #require(ContinuousClock.now < deadline, "timed out waiting for \(what)")
        try await Task.sleep(for: .milliseconds(2))
    }
}

/// One session, one API client and ONE stream manager, so two view models can share the manager like the app does.
@MainActor
private struct Harness {
    let session: URLSession
    let apiClient: APIClient
    let manager: ChatStreamManager
    let config: ServerConfigStore

    init(_ suite: String = #function) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        config = ServerConfigStore(userDefaults: defaults)
        session = ChatDetailMockURLProtocol.makeSession()
        apiClient = APIClient(session: session, serverConfig: config)
        manager = ChatStreamManager(sseClient: SSEClient(session: session))
    }

    func makeViewModel(chatId: String = "c1", title: String? = nil) -> ChatDetailViewModel {
        ChatDetailViewModel(
            chatId: chatId, title: title, apiClient: apiClient, streamManager: manager, serverConfig: config)
    }
}

@MainActor
@Suite("ChatDetailViewModel", .serialized)
struct ChatDetailViewModelTests {
    @Test("loadHistory shows the desktop-shaped messages converted from the database rows")
    func loadHistoryConvertsDatabaseRows() async throws {
        let recorder = RequestRecorder()
        serve(history: historyRowsJSON, recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        #expect(recorder.lines == ["GET /api/v1/chat/c1/page"])
        #expect(vm.messages.map(\.displayText) == ["hi", "hello"])
        #expect(vm.messages.allSatisfy { $0.raw.keys.contains("chatId") == false && $0.timestampMs != nil })
        #expect(vm.hasLoadedHistory)
        #expect(vm.errorMessage == nil)
    }

    @Test("a chat with no server record yet loads as an empty transcript, not an error")
    func aNewChatLoadsAsEmpty() async throws {
        serve(history: "[]", recorder: RequestRecorder())
        let vm = Harness().makeViewModel(chatId: "brand-new")
        await vm.loadHistory()
        #expect(vm.messages.isEmpty)
        #expect(vm.hasLoadedHistory)
        #expect(vm.errorMessage == nil)
    }

    @Test("a failed history load blocks sending, keeps the draft, and posts nothing")
    func aFailedHistoryLoadBlocksSending() async throws {
        let recorder = RequestRecorder()
        serve(history: envelope404, historyStatus: 500, recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        #expect(vm.hasLoadedHistory == false)
        #expect(vm.errorMessage == "Chat not found")

        vm.composerText = "hello"
        #expect(vm.canSend == false)
        await vm.sendMessage()
        #expect(recorder.lines == ["GET /api/v1/chat/c1/page"])
        #expect(vm.composerText == "hello")
        #expect(vm.messages.isEmpty)
    }

    @Test("a cancelled history load is not shown as an error")
    func aCancelledHistoryLoadIsNotAnError() async throws {
        ChatDetailMockURLProtocol.handler = { _ in throw URLError(.cancelled) }
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        #expect(vm.errorMessage == nil)
        #expect(vm.hasLoadedHistory == false)
    }

    /// The server reads the conversation from its own rows (desktop spec 2026-10-01 §C1): a send carries the new
    /// question and asks for protocol 2 — not the whole transcript, on the phone's uplink, every time.
    @Test("sendMessage posts the new question only, and asks for protocol 2")
    func sendMessageSendsTheQuestion() async throws {
        let recorder = RequestRecorder()
        serve(history: historyRowsJSON, reply: helloReply, recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        await vm.sendMessage()

        let body = try recorder.onlyJSONBody(forPOST: "/api/v1/chat")
        #expect(Set(body.keys) == ["id", "message", "advancedTools", "protocol"])
        #expect(body["id"] as? String == "c1")
        #expect(body["protocol"] as? Int == 2)
        #expect((body["advancedTools"] as? [Any])?.isEmpty == true)
        // The new message, with a lowercase UUID id and a numeric timestamp.
        let question = try #require(body["message"] as? [String: Any])
        #expect(question["role"] as? String == "user")
        #expect(question["content"] as? String == "hey")
        let id = try #require(question["id"] as? String)
        #expect(id == id.lowercased() && UUID(uuidString: id) != nil)
        #expect(question["timestamp"] is NSNumber)
    }

    @Test("a quote goes with the next message, once, and a quote alone is not sent")
    func aQuoteIsSentWithTheQuestion() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", reply: helloReply, recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()

        vm.askAbout("  a quoted line ")
        #expect(vm.quote == "a quoted line")
        #expect(vm.canSend == false)  // a quote is asked about, not sent by itself

        vm.askAbout("the one that counts")
        #expect(vm.quote == "the one that counts")  // one at a time: a new one replaces it

        vm.composerText = "why?"
        await vm.sendMessage()
        let body = try recorder.onlyJSONBody(forPOST: "/api/v1/chat")
        let question = try #require(body["message"] as? [String: Any])
        #expect(question["content"] as? String == "> the one that counts\n\nwhy?")
        #expect(vm.quote == nil)
    }

    @Test("a quote can be let go of, and asks for the composer's focus when set")
    func aQuoteCanBeRemoved() async throws {
        serve(history: "[]", recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        let focus = vm.composerFocusRequest

        vm.askAbout("line")
        #expect(vm.composerFocusRequest == focus + 1)
        vm.removeQuote()
        #expect(vm.quote == nil)
        vm.askAbout("   ")
        #expect(vm.quote == nil)  // nothing selected is nothing to ask about
    }

    @Test("the sent text is trimmed of surrounding whitespace and newlines, and the composer is cleared")
    func theSentTextIsTrimmed() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", reply: helloReply, recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        vm.composerText = "  hi there \n"
        await vm.sendMessage()

        let body = try recorder.onlyJSONBody(forPOST: "/api/v1/chat")
        let question = try #require(body["message"] as? [String: Any])
        #expect(question["content"] as? String == "hi there")  // inner space kept, both ends trimmed
        #expect(vm.composerText.isEmpty)
    }

    @Test("sendMessage streams the reply to completion: final messages from `done`, title event applied, composer cleared")
    func sendMessageStreamsToCompletion() async throws {
        serve(history: "[]", reply: helloReply, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        await vm.sendMessage()
        #expect(vm.messages.map(\.displayText) == ["hey", "Hello!"])
        #expect(vm.status == .idle)
        #expect(vm.composerText.isEmpty)
        #expect(vm.chatTitle == "Greeting")
        #expect(vm.errorMessage == nil)
    }

    @Test("empty or whitespace-only drafts are not sent")
    func emptyDraftsAreNotSent() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", reply: helloReply, recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        for draft in ["", "   ", "\n \n"] {
            vm.composerText = draft
            #expect(vm.canSend == false)
            await vm.sendMessage()
        }
        #expect(recorder.lines == ["GET /api/v1/chat/c1/page"])
        #expect(vm.messages.isEmpty)
    }

    @Test("a server error frame ends the turn in the error state with the message shown, and the composer usable again")
    func aServerErrorFrameEndsTheTurnInAnErrorState() async throws {
        serve(history: "[]", reply: #"data: {"type":"error","error":"Invalid API key"}\#n\#n"#, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        await vm.sendMessage()
        #expect(vm.errorMessage == "Invalid API key")
        #expect(vm.liveRunError?.message == "Invalid API key")
        #expect(vm.liveRunError?.runId == vm.messages.last(where: { $0.role == "user" })?.id)
        #expect(vm.showsErrorAlert == false)  // pinned to its run instead
        #expect(vm.status == .error)  // not overwritten by a trailing idle
        vm.composerText = "again"
        #expect(vm.canSend)
    }

    @Test("a second send while a turn is in flight is ignored", .timeLimit(.minutes(1)))
    func aSecondSendWhileInFlightIsIgnored() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", reply: partialReply, holdReplyOpen: true, recorder: recorder)
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "first"
        let firstSend = Task { await vm.sendMessage() }
        try await waitUntil("the partial reply to arrive") { vm.messages.last?.displayText == "Hel" }

        vm.composerText = "second"
        #expect(vm.canSend == false)
        await vm.sendMessage()
        #expect(recorder.lines.filter { $0 == "POST /api/v1/chat" }.count == 1)
        #expect(vm.composerText == "second")

        harness.session.invalidateAndCancel()  // end the held-open connection so the first send returns
        await firstSend.value
    }

    @Test("loadHistory during a turn (pull-to-refresh) does not replace the streaming reply with database rows", .timeLimit(.minutes(1)))
    func loadHistoryDoesNotReplaceAStreamingReply() async throws {
        let recorder = RequestRecorder()
        serve(history: historyRowsJSON, reply: partialReply, holdReplyOpen: true, recorder: recorder)
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        let send = Task { await vm.sendMessage() }
        try await waitUntil("the partial reply to arrive") { vm.messages.last?.displayText == "Hel" }
        let messagesBefore = vm.messages
        let statusBefore = vm.status

        await vm.loadHistory()  // what a pull-to-refresh does while the turn is still streaming

        #expect(recorder.lines.filter { $0 == "GET /api/v1/chat/c1/page" }.count == 1)  // only the setup load, no second fetch
        #expect(vm.messages == messagesBefore)
        #expect(vm.messages.last?.displayText == "Hel")
        #expect(vm.status == statusBefore)
        #expect(vm.errorMessage == nil)
        #expect(vm.hasLoadedHistory)

        harness.session.invalidateAndCancel()  // end the held-open connection so the send returns
        await send.value
    }

    @Test("returning to a chat whose reply is still streaming re-attaches to it instead of reloading history", .timeLimit(.minutes(1)))
    func onAppearReattachesToAnInFlightTurn() async throws {
        let recorder = RequestRecorder()
        serve(history: historyRowsJSON, reply: partialReply, holdReplyOpen: true, recorder: recorder)
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        let first = harness.makeViewModel()
        await first.loadHistory()
        first.composerText = "hey"
        let firstSend = Task { await first.sendMessage() }
        try await waitUntil("the partial reply to arrive") { await harness.manager.isStreaming("c1") && first.messages.last?.displayText == "Hel" }

        // A new view model for the same chat (what leaving and returning creates) shares the manager.
        let second = harness.makeViewModel()
        let appear = Task { await second.onAppear() }
        try await waitUntil("the re-attached view model to show the partial reply") {
            second.messages.last?.displayText == "Hel"
        }
        #expect(second.hasLoadedHistory)
        #expect(second.status == .streaming)
        #expect(recorder.lines.filter { $0 == "GET /api/v1/chat/c1/page" }.count == 1)  // only the first view model's load

        harness.session.invalidateAndCancel()
        await firstSend.value
        await appear.value
    }

    // MARK: - Pending row (waiting for the first token)

    @Test("showsPendingRow is false while idle: on an empty chat, after a history ending with the user's message, and after a completed turn")
    func pendingRowIsHiddenWhileIdle() async throws {
        serve(history: "[]", reply: helloReply, recorder: RequestRecorder())
        let empty = Harness().makeViewModel()
        await empty.loadHistory()
        #expect(empty.messages.isEmpty)
        #expect(empty.showsPendingRow == false)

        serve(history: userOnlyHistoryJSON, recorder: RequestRecorder())
        let endsWithUser = Harness().makeViewModel()
        await endsWithUser.loadHistory()
        #expect(endsWithUser.messages.map(\.role) == ["user"])
        #expect(endsWithUser.showsPendingRow == false)

        serve(history: "[]", reply: helloReply, recorder: RequestRecorder())
        let completed = Harness().makeViewModel()
        await completed.loadHistory()
        completed.composerText = "hey"
        await completed.sendMessage()
        #expect(completed.status == .idle)
        #expect(completed.showsPendingRow == false)
    }

    @Test("showsPendingRow is true from tapping send until the server's first assistant message", .timeLimit(.minutes(1)))
    func pendingRowShowsWhileWaitingForTheFirstToken() async throws {
        let recorder = RequestRecorder()
        // The server has accepted the turn but sent nothing yet (a reasoning model thinking).
        serve(history: "[]", reply: "", holdReplyOpen: true, recorder: recorder)
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        let send = Task { await vm.sendMessage() }
        try await waitUntil("the chat POST to reach the server") { recorder.lines.contains("POST /api/v1/chat") }

        #expect(vm.isTurnInFlight)
        #expect(vm.messages.map(\.role) == ["user"])  // the last message is the user's: nothing else on screen yet
        #expect(vm.showsPendingRow)

        harness.session.invalidateAndCancel()  // end the held-open connection so the send returns
        await send.value
    }

    @Test("showsPendingRow turns false once the assistant's partial reply arrives, while the turn is still in flight", .timeLimit(.minutes(1)))
    func pendingRowHidesOnceTheAssistantReplies() async throws {
        serve(history: "[]", reply: partialReply, holdReplyOpen: true, recorder: RequestRecorder())
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        let send = Task { await vm.sendMessage() }
        try await waitUntil("the partial reply to arrive") { vm.messages.last?.displayText == "Hel" }

        #expect(vm.isTurnInFlight)
        #expect(vm.messages.last?.role == "assistant")
        #expect(vm.showsPendingRow == false)

        harness.session.invalidateAndCancel()
        await send.value
    }

    @Test("after a tool result with no answer yet, the turn's live timeline shows progress instead of the dots", .timeLimit(.minutes(1)))
    func liveTimelineReplacesTheDotsAfterAToolResult() async throws {
        serve(history: "[]", reply: toolResultReply, holdReplyOpen: true, recorder: RequestRecorder())
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        let send = Task { await vm.sendMessage() }
        try await waitUntil("the tool result to arrive") { vm.messages.last?.role == "toolResult" }

        #expect(vm.isTurnInFlight)
        #expect(vm.showsPendingRow == false)
        let turnId = try #require(vm.streamingTurnId)
        guard case .assistantTurn(let turn)? = vm.segments.last else {
            Issue.record("no turn")
            return
        }
        #expect(turn.id == turnId)
        #expect(TranscriptRules.timelineIsLive(turn, isStreaming: true))

        harness.session.invalidateAndCancel()
        await send.value
    }

    // MARK: - Stop

    @Test("stop() ends an in-flight turn: the partial reply stays, no error appears, and the composer works again", .timeLimit(.minutes(1)))
    func stopEndsAnInFlightTurn() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", reply: partialReply, holdReplyOpen: true, recorder: recorder)
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }  // ends the held-open connection even if an assertion below fails
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        let send = Task { await vm.sendMessage() }
        try await waitUntil("the partial reply to arrive") { vm.messages.last?.displayText == "Hel" }
        #expect(vm.isTurnInFlight)
        #expect(vm.canSend == false)

        await vm.stop()
        try await waitUntil("the stopped turn to end") { vm.status == .idle }
        await send.value  // `sendMessage` returns by itself: the observer's stream was finished (bounded by the time limit)

        #expect(vm.status == .idle)
        #expect(vm.messages.map(\.role) == ["user", "assistant"])
        #expect(vm.messages.last?.displayText == "Hel")  // the partial reply stays
        #expect(vm.errorMessage == nil)  // a stop is not an error
        #expect(vm.showsPendingRow == false)
        #expect(await harness.manager.isStreaming("c1") == false)
        #expect(recorder.lines.filter { $0 == "POST /api/v1/chat" }.count == 1)
        #expect(vm.stopCount == 1)  // the Stop haptic's trigger
        #expect(vm.completedTurnCount == 0)  // a stop is not a completion: no success haptic

        vm.composerText = "again"
        #expect(vm.canSend)
    }

    @Test("stop() with no turn in flight does nothing")
    func stopWhileIdleIsANoOp() async throws {
        let recorder = RequestRecorder()
        serve(history: historyRowsJSON, recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        let before = vm.messages

        await vm.stop()

        #expect(vm.status == .idle)
        #expect(vm.messages == before)
        #expect(vm.errorMessage == nil)
        #expect(recorder.lines == ["GET /api/v1/chat/c1/page"])
        #expect(vm.stopCount == 0)  // nothing was in flight, so no stop haptic either
    }

    /// The race a review round found: `isTurnInFlight` is only a local mirror of the manager's
    /// state, current up to the last update this view model has drained. A turn can finish (or
    /// fail) on the manager side, removing its entry, before that drain catches up — the update
    /// is sitting in the stream, not yet processed. A `stop()` landing in that exact window must
    /// not mark the turn as stopped, because `cancel(_:)` finds nothing left to cancel there.
    ///
    /// The precise interleaving is a suspend-point race between two concurrently scheduled
    /// MainActor tasks (the manager's background task finishing and removing its entry, versus
    /// this view model's own `consume` loop draining the buffered result) and cannot be
    /// constructed deterministically from test code — Swift's Task scheduler gives no seam to
    /// pin that ordering, and any attempt would be flaky (sometimes reproducing, sometimes not).
    /// What follows instead is a DETERMINISTIC construction of the identical code path and the
    /// identical bug class — `isTurnInFlight` reading stale-true locally while `cancel(_:)`
    /// legitimately has nothing left to cancel — using the re-attach machinery's own documented
    /// "single observer, latest wins" rule: a superseded view model's `consume` loop exits
    /// quietly (its continuation is finished by `attach`, not fed a final `.finished`/`.failed`),
    /// so its `status` freezes at whatever it last was and never updates again, same as a stale
    /// read would. See `ChatStreamManagerTests` for `cancel(_:)`'s own true/false coverage.
    @Test(
        "stop() does not mark a turn as stopped when cancel(_:) finds nothing to cancel, even though isTurnInFlight still reads stale-true",
        .timeLimit(.minutes(1)))
    func stopDoesNotMislabelATurnCancelCouldNotFind() async throws {
        serve(history: "[]", reply: partialReply, holdReplyOpen: true, recorder: RequestRecorder())
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }

        let stale = harness.makeViewModel()
        await stale.loadHistory()
        stale.composerText = "hey"
        let staleSend = Task { await stale.sendMessage() }
        try await waitUntil("the partial reply to arrive") { stale.messages.last?.displayText == "Hel" }
        #expect(stale.isTurnInFlight)

        // A second view model re-attaches to the same turn: `attach` ends `stale`'s own observer
        // stream (single observer, latest wins), so `stale`'s `consume` loop exits quietly and
        // nothing will ever update its `status` again — frozen mid-flight, exactly like a stale
        // read caught between the manager finishing and this view model draining that news.
        let current = harness.makeViewModel()
        let appear = Task { await current.onAppear() }
        try await waitUntil("the re-attached view model to show the partial reply") {
            current.messages.last?.displayText == "Hel"
        }
        await staleSend.value  // `stale`'s own sendMessage() returns once its stream ends
        #expect(stale.isTurnInFlight)  // frozen true: superseded, but never told the turn moved on

        // The re-attached (current) view model legitimately stops the real turn.
        await current.stop()
        try await waitUntil("the stopped turn to end") { current.status == .idle }
        await appear.value
        #expect(current.stopCount == 1)
        #expect(await harness.manager.isStreaming("c1") == false)

        // The stale view model, still believing a turn is in flight, is asked to stop it too.
        // cancel(_:) finds nothing (already cancelled by `current`) and returns false, so this
        // must NOT be counted as a stop.
        await stale.stop()
        #expect(stale.stopCount == 0)
        #expect(stale.completedTurnCount == 0)
        #expect(stale.errorMessage == nil)

        harness.session.invalidateAndCancel()
    }

    // MARK: - Haptic triggers (sendCount, completedTurnCount, stopCount)

    @Test("a turn that completes normally bumps completedTurnCount once, and never stopCount")
    func normalCompletionBumpsCompletedTurnCount() async throws {
        serve(history: "[]", reply: helloReply, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        #expect(vm.completedTurnCount == 0)
        vm.composerText = "hey"
        await vm.sendMessage()
        #expect(vm.completedTurnCount == 1)
        #expect(vm.stopCount == 0)
    }

    @Test("two turns that both complete normally bump completedTurnCount twice")
    func twoTurnsBumpCompletedTurnCountTwice() async throws {
        serve(history: "[]", reply: helloReply, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        await vm.sendMessage()
        #expect(vm.completedTurnCount == 1)

        vm.composerText = "again"
        await vm.sendMessage()
        #expect(vm.completedTurnCount == 2)
    }

    @Test(
        "a normal completion after an earlier stop is not suppressed: turnWasStopped does not leak across turns",
        .timeLimit(.minutes(1)))
    func aNormalCompletionAfterAnEarlierStopIsNotSuppressed() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", reply: partialReply, holdReplyOpen: true, recorder: recorder)
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "first"
        let firstSend = Task { await vm.sendMessage() }
        try await waitUntil("the partial reply to arrive") { vm.messages.last?.displayText == "Hel" }

        await vm.stop()
        try await waitUntil("the stopped turn to end") { vm.status == .idle }
        await firstSend.value
        #expect(vm.stopCount == 1)
        #expect(vm.completedTurnCount == 0)

        // A second, fresh turn on the SAME view model — this one completes normally.
        serve(history: "[]", reply: helloReply, recorder: RequestRecorder())
        vm.composerText = "second"
        await vm.sendMessage()

        #expect(vm.status == .idle)
        #expect(vm.completedTurnCount == 1)  // the second turn's own success, not swallowed by the first's stop
        #expect(vm.stopCount == 1)  // unchanged: no second stop happened
    }

    @Test("a turn that ends in a server error frame does not bump completedTurnCount or stopCount")
    func aFailedTurnDoesNotBumpCompletedTurnCount() async throws {
        serve(history: "[]", reply: #"data: {"type":"error","error":"Invalid API key"}\#n\#n"#, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        await vm.sendMessage()
        #expect(vm.errorMessage == "Invalid API key")
        #expect(vm.completedTurnCount == 0)
        #expect(vm.stopCount == 0)
        // Send still fires at tap-time regardless of the eventual outcome — it is never
        // retroactively suppressed once the turn goes on to fail.
        #expect(vm.sendCount == 1)
    }

    @Test("onAppear with nothing in flight loads history instead of consuming a stream, so completedTurnCount never moves")
    func reattachWithNothingInFlightDoesNotBumpCompletedTurnCount() async throws {
        serve(history: historyRowsJSON, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.onAppear()
        #expect(vm.hasLoadedHistory)
        #expect(vm.completedTurnCount == 0)
    }

    @Test("a chat made on the phone is ready to send at once: no history is asked for")
    func aNewChatSkipsTheHistoryRead() async throws {
        let recorder = RequestRecorder()
        serve(history: historyRowsJSON, recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.onAppear(isNew: true)
        #expect(vm.hasLoadedHistory)
        #expect(vm.messages.isEmpty)
        #expect(!recorder.lines.contains { $0.contains("/page") })
        vm.composerText = "hey"
        #expect(vm.canSend)
    }

    @Test("sendMessage bumps sendCount once per accepted send; a send canSend rejects does not")
    func sendCountBumpsOnlyOnAcceptedSends() async throws {
        serve(history: historyRowsJSON, reply: helloReply, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        #expect(vm.sendCount == 0)
        vm.composerText = "hey"
        await vm.sendMessage()
        #expect(vm.sendCount == 1)

        vm.composerText = "   "  // blank: canSend is false
        await vm.sendMessage()
        #expect(vm.sendCount == 1)
    }

    @Test("loadHistory does not bump sendCount")
    func loadHistoryDoesNotBumpSendCount() async throws {
        serve(history: historyRowsJSON, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        #expect(vm.sendCount == 0)
    }

    @Test(
        "onAppear re-attaching to a turn already in flight does not bump sendCount or completedTurnCount",
        .timeLimit(.minutes(1)))
    func reattachToARunningTurnDoesNotBumpSendCount() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", reply: partialReply, holdReplyOpen: true, recorder: recorder)
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let first = harness.makeViewModel()
        await first.loadHistory()
        first.composerText = "hey"
        let firstSend = Task { await first.sendMessage() }
        try await waitUntil("the partial reply to arrive") {
            await harness.manager.isStreaming("c1") && first.messages.last?.displayText == "Hel"
        }
        #expect(first.sendCount == 1)

        let second = harness.makeViewModel()
        let appear = Task { await second.onAppear() }
        try await waitUntil("the re-attached view model to show the partial reply") {
            second.messages.last?.displayText == "Hel"
        }
        #expect(second.sendCount == 0)
        #expect(second.completedTurnCount == 0)

        harness.session.invalidateAndCancel()
        await firstSend.value
        await appear.value
    }

    @Test("stop() from a view model that is not in a turn does not cancel a turn another view model started", .timeLimit(.minutes(1)))
    func stopFromAnIdleViewModelLeavesTheTurnAlone() async throws {
        serve(history: "[]", reply: partialReply, holdReplyOpen: true, recorder: RequestRecorder())
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let first = harness.makeViewModel()
        await first.loadHistory()
        first.composerText = "hey"
        let send = Task { await first.sendMessage() }
        try await waitUntil("the partial reply to arrive") {
            await harness.manager.isStreaming("c1") && first.messages.last?.displayText == "Hel"
        }

        // Same chat, same manager, but this view model never attached to the turn, so it is idle.
        let bystander = harness.makeViewModel()
        #expect(bystander.status == .idle)
        await bystander.stop()

        #expect(await harness.manager.isStreaming("c1"))
        #expect(first.isTurnInFlight)
        #expect(first.messages.last?.displayText == "Hel")

        harness.session.invalidateAndCancel()
        await send.value
    }

    @Test("the navigation title is New chat until a chat is known to have been opened with messages, and Chat after that")
    func displayTitle() async throws {
        serve(history: historyRowsJSON, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        #expect(vm.displayTitle == "New chat")
        await vm.loadHistory()
        #expect(vm.displayTitle == "Chat")
    }

    /// The flicker the owner reported: the title used to flip to "Chat" the moment the first message
    /// was sent and again to the generated title a few seconds later. A chat that started empty now
    /// keeps "New chat" until a real title arrives.
    @Test("a chat that started empty keeps New chat for the whole first turn", .timeLimit(.minutes(1)))
    func aNewChatKeepsItsTitleUntilOneIsGenerated() async throws {
        serve(history: "[]", reply: partialReply, holdReplyOpen: true, recorder: RequestRecorder())
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        #expect(vm.displayTitle == "New chat")

        vm.composerText = "hey"
        let send = Task { await vm.sendMessage() }
        try await waitUntil("the partial reply to arrive") { vm.messages.last?.displayText == "Hel" }
        // The transcript now holds the user's message and the reply so far, and still no title.
        #expect(vm.messages.count == 2)
        #expect(vm.displayTitle == "New chat")

        harness.session.invalidateAndCancel()
        await send.value
    }

    @Test("a chat that started empty shows the generated title as soon as the title event arrives")
    func aNewChatShowsTheGeneratedTitle() async throws {
        serve(history: "[]", reply: helloReply, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        await vm.sendMessage()
        #expect(vm.displayTitle == "Greeting")
    }

    /// A pull-to-refresh after the first turn must not turn the new chat into one "opened with
    /// messages", which would change the title from "New chat" to "Chat" under the user.
    @Test("reloading a new chat's history after its first turn keeps the New chat title")
    func reloadingAfterTheFirstTurnKeepsNewChat() async throws {
        serve(history: "[]", reply: partialReply, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        await vm.sendMessage()
        #expect(vm.status == .idle)

        serve(history: historyRowsJSON, recorder: RequestRecorder())  // the server now has the turn
        await vm.loadHistory()
        #expect(vm.messages.isEmpty == false)
        #expect(vm.displayTitle == "New chat")
    }

    @Test("a title too long for a title bar is cut for display, and the chat keeps the server's text")
    func aLongTitleIsCutForDisplay() async throws {
        serve(history: "[]", recorder: RequestRecorder())
        let long = (1...40).map { "word\($0)" }.joined(separator: " ")  // 270 characters, no stray spaces
        try #require(long.count > 80)
        let vm = Harness().makeViewModel(title: long)
        #expect(vm.chatTitle == long)  // the server's title is kept whole
        #expect(vm.displayTitle.count == 81)  // 80 characters plus the ellipsis
        #expect(vm.displayTitle.hasSuffix("…"))
        #expect(long.hasPrefix(vm.displayTitle.dropLast()))  // the cut text is the start of the title

        // A title that fits is shown exactly as it is.
        let short = String(long.prefix(80))
        #expect(Harness().makeViewModel(title: short).displayTitle == short)
    }

    /// The cut can land on a space, and a space left in front of the ellipsis would look like a typo.
    @Test("a title cut in the middle of a space loses that space, not just the rest of the title")
    func aTitleCutOnASpaceKeepsNoTrailingSpace() async throws {
        serve(history: "[]", recorder: RequestRecorder())
        let head = String(repeating: "x", count: 79)
        let long = head + " and more text after the cut"
        try #require(Array(long)[79] == " ")  // the 80th character, where the cut falls
        let vm = Harness().makeViewModel(title: long)
        #expect(vm.displayTitle == head + "…")
        #expect(vm.displayTitle.count == 80)  // 79 characters plus the ellipsis, the space dropped
    }

    // MARK: - Titles on one line, and the empty state

    @Test("a chat opened with a title shows it, collapsed to one line")
    func initialTitleIsShownOnOneLine() async throws {
        serve(history: "[]", recorder: RequestRecorder())
        #expect(Harness().makeViewModel(title: "Trip planning").displayTitle == "Trip planning")
        #expect(Harness().makeViewModel(title: "Line one\n\nLine two").displayTitle == "Line one Line two")
        #expect(Harness().makeViewModel(title: "  \n ").displayTitle == "New chat")
    }

    @Test("a title event is collapsed to one line too", .timeLimit(.minutes(1)))
    func titleEventIsCollapsed() async throws {
        serve(history: "[]", reply: multilineTitleReply, recorder: RequestRecorder())
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        await vm.sendMessage()
        #expect(vm.chatTitle == "First line Second line")
    }

    @Test("applyExternalRename sets the title, collapsed to one line, overriding what was there")
    func applyExternalRenameSetsTheTitle() async throws {
        serve(history: "[]", recorder: RequestRecorder())
        let vm = Harness().makeViewModel(title: "Old title")
        vm.applyExternalRename("New\n\ntitle")
        #expect(vm.displayTitle == "New title")
    }

    @Test("applyExternalRename on a blank string does nothing, never clearing a real title")
    func applyExternalRenameIgnoresABlankTitle() async throws {
        serve(history: "[]", recorder: RequestRecorder())
        let vm = Harness().makeViewModel(title: "Trip planning")
        vm.applyExternalRename("   ")
        #expect(vm.displayTitle == "Trip planning")
        vm.applyExternalRename(nil)
        #expect(vm.displayTitle == "Trip planning")
    }

    @Test("showsEmptyState is true only for a loaded, empty, idle chat")
    func emptyStateOnlyForALoadedEmptyChat() async throws {
        serve(history: "[]", recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        #expect(vm.showsEmptyState == false)  // not loaded yet: the screen must not flash "empty"
        await vm.loadHistory()
        #expect(vm.showsEmptyState)
    }

    @Test("showsEmptyState is false when the transcript has messages")
    func noEmptyStateWithMessages() async throws {
        serve(history: historyRowsJSON, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        #expect(vm.showsEmptyState == false)
    }

    @Test("showsEmptyState is false after a failed load")
    func noEmptyStateAfterAFailedLoad() async throws {
        serve(history: envelope404, historyStatus: 500, recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        #expect(vm.hasLoadedHistory == false)
        #expect(vm.showsEmptyState == false)
    }

    @Test("showsEmptyState is false while a turn is in flight", .timeLimit(.minutes(1)))
    func noEmptyStateWhileATurnIsInFlight() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", reply: "", holdReplyOpen: true, recorder: recorder)
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        let vm = harness.makeViewModel()
        await vm.loadHistory()
        vm.composerText = "hey"
        let send = Task { await vm.sendMessage() }
        try await waitUntil("the chat POST to reach the server") { recorder.lines.contains("POST /api/v1/chat") }
        #expect(vm.showsEmptyState == false)
        harness.session.invalidateAndCancel()
        await send.value
    }

    /// The test above cannot pin the `!isTurnInFlight` clause: `sendMessage` appends the user message
    /// before the turn starts, so `messages` is never empty during it. Only the re-attach branch of
    /// `onAppear` (in flight, `hasLoadedHistory` set, transcript not delivered yet) can be empty.
    @Test(
        "showsEmptyState is false when re-attached to a turn in flight whose transcript is still empty",
        .timeLimit(.minutes(1)))
    func noEmptyStateWhenReattachedToAnEmptyTurn() async throws {
        serve(history: "[]", reply: "", holdReplyOpen: true, recorder: RequestRecorder())
        defer { ChatDetailMockURLProtocol.holdsChatPostOpen = false }
        let harness = Harness()
        defer { harness.session.invalidateAndCancel() }
        // A turn already in flight for this chat, started with an empty transcript, as another observer would leave it.
        _ = await harness.manager.send(chatId: "c1", messages: [], serverConfig: harness.config)
        let vm = harness.makeViewModel()
        let appear = Task { await vm.onAppear() }
        // The status settles at `.submitted` (the held-open reply sends nothing), so wait on the flags, not on `.streaming`.
        try await waitUntil("the view model to re-attach") { vm.hasLoadedHistory && vm.isTurnInFlight }
        #expect(vm.messages.isEmpty)
        #expect(vm.showsEmptyState == false)
        harness.session.invalidateAndCancel()
        await appear.value
    }

    @Test("a question handed over from Health is sent once, however often it is handed")
    func sendInitialSendsOnce() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", reply: helloReply, recorder: recorder)
        let vm = Harness().makeViewModel(chatId: "from-health")
        await vm.loadHistory()
        let text = "```actovia-health\n{\"steps\":1}\n```\n\nWhy am I tired?"
        await vm.sendInitial(text)
        await vm.sendInitial(text)
        #expect(recorder.lines.filter { $0 == "POST /api/v1/chat" }.count == 1)
        // The request carries the new message alone (`message`) or the whole transcript (`messages`), last.
        let body = try recorder.onlyJSONBody(forPOST: "/api/v1/chat")
        let sent = try #require(body["message"] ?? (body["messages"] as? [Any])?.last)
        let json = String(decoding: try JSONSerialization.data(withJSONObject: sent), as: UTF8.self)
        #expect(json.contains("actovia-health"))
        #expect(json.contains("Why am I tired?"))
    }

    @Test("a question handed over from Health waits in the composer when the history failed to load")
    func sendInitialKeepsTheQuestionWhenHistoryFailed() async {
        let recorder = RequestRecorder()
        serve(history: "[]", historyStatus: 500, reply: helloReply, recorder: recorder)
        let vm = Harness().makeViewModel(chatId: "from-health")
        await vm.loadHistory()
        #expect(!vm.hasLoadedHistory)
        await vm.sendInitial("Why am I tired?")
        #expect(!recorder.lines.contains("POST /api/v1/chat"))
        #expect(vm.composerText == "Why am I tired?")
    }
}

@MainActor
@Suite("ChatDetailViewModel: the memory foot", .serialized)
struct ChatDetailMemoryFootTests {
    nonisolated private static let usage = #"{"u1":[{"id":"m2","key":"Work setup","section":"profile"}]}"#
    nonisolated private static let reply = """
        data: {"type":"memories_used","runId":"live-run","memories":[{"id":"m1","key":"Music","section":"topic"}]}\n\n\
        data: {"type":"message_update","message":{"id":"a2","role":"assistant","content":"Hel"}}\n\n\
        data: {"type":"tool_call_end","toolCallId":"k1","toolName":"update_memory","isError":false}\n\n\
        data: {"type":"message_update","message":{"id":"a2","role":"assistant","content":"Hello"}}\n\n
        """

    private func serveMemory() {
        ChatDetailMockURLProtocol.holdsChatPostOpen = false
        ChatDetailMockURLProtocol.handler = { request in
            switch (request.httpMethod ?? "GET", request.url?.path ?? "") {
            case ("GET", "/api/v1/chat/c1/page"): (200, Data(ChatPageFixture.page(historyRowsJSON).utf8))
            case ("GET", "/api/v1/memory/usage"): (200, Data(Self.usage.utf8))
            case ("GET", "/api/v1/memory"): (200, Data("[]".utf8))
            case ("POST", "/api/v1/chat"): (200, Data(Self.reply.utf8))
            default: (404, Data(envelope404.utf8))
            }
        }
    }

    @Test("history usage lands by run; memories_used and update_memory's end reach the live run, not the settled one")
    func streamAndHistory() async throws {
        serveMemory()
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        await vm.loadMemoryUsage()
        let settled = vm.memoryFoot.run("u1")
        #expect(settled.used.map(\.key) == ["Work setup"])
        let fired = Mutex(0)
        withObservationTracking {
            _ = (settled.used, settled.live, settled.undo)
        } onChange: {
            fired.withLock { $0 += 1 }
        }
        vm.composerText = "hey"
        await vm.sendMessage()
        try await waitUntil("the reply settles") { vm.status == .idle && vm.messages.last?.displayText == "Hello" }
        #expect(vm.memoryFoot.run("live-run").used.map(\.key) == ["Music"])
        let sent = try #require(vm.messages.last { $0.role == "user" })
        #expect(vm.memoryFoot.run(sent.runId ?? sent.id).live, "the run whose update_memory ended here is live")
        #expect(fired.withLock { $0 } == 0, "the settled run's foot was not touched by the streaming one")
        ChatDetailMockURLProtocol.handler = nil
    }

    @Test("a new, empty chat asks for no usage; This is wrong replaces the composer's text and asks for focus")
    func prefill() async throws {
        let recorder = RequestRecorder()
        serve(history: "[]", recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        await vm.loadMemoryUsage()
        #expect(recorder.lines == ["GET /api/v1/chat/c1/page"])
        vm.composerText = "draft"
        vm.memoryFoot.onWrong("The memory about 'Music' is wrong: ")
        #expect(vm.composerText == "The memory about 'Music' is wrong: ")
        #expect(vm.composerFocusRequest == 1)
        ChatDetailMockURLProtocol.handler = nil
    }
}

/// A chat's history a page at a time (desktop spec 2026-10-01 §C3–C4): the phone opens on the newest page, puts older
/// ones in above it, and resolves a citation of a source found in a run it has not loaded.
@MainActor
@Suite("ChatDetailViewModel: older pages", .serialized)
struct ChatDetailOlderPagesTests {
    nonisolated private static let newest = #"""
        [{"id":"u2","runId":"u2","role":"user","content":"second","createdAt":"2026-09-18T12:01:00.000Z"},
         {"id":"a2","runId":"u2","role":"assistant","content":[{"type":"text","text":"As 【1-source】 says."}],"stopReason":"stop","createdAt":"2026-09-18T12:01:01.000Z"}]
        """#
    nonisolated private static let older = #"""
        [{"id":"u1","runId":"u1","role":"user","content":"first","createdAt":"2026-09-18T12:00:00.000Z"},
         {"id":"a0","runId":"u1","role":"assistant","content":[{"type":"toolCall","id":"k1","name":"web_search","arguments":{"query":"q"}}],"stopReason":"toolUse","createdAt":"2026-09-18T12:00:00.500Z"},
         {"id":"t1","runId":"u1","role":"toolResult","toolCallId":"k1","toolName":"web_search","content":[],"details":[{"rank":1,"link":"https://a.example/","title":"A","snippet":""}],"isError":false,"createdAt":"2026-09-18T12:00:00.700Z"},
         {"id":"a1","runId":"u1","role":"assistant","content":[{"type":"text","text":"One."}],"stopReason":"stop","createdAt":"2026-09-18T12:00:01.000Z"}]
        """#
    nonisolated private static let sources = #"[{"rank":1,"link":"https://a.example/","title":"A","runId":"u1"}]"#

    private func serve(recorder: RequestRecorder, newestPage: String? = nil, row: String? = nil) {
        ChatDetailMockURLProtocol.holdsChatPostOpen = false
        let newest = newestPage ?? ChatPageFixture.page(Self.newest, hasOlder: true, olderCursor: "u2", sources: Self.sources)
        ChatDetailMockURLProtocol.handler = { request in
            let path = request.url?.path ?? ""
            let query = request.url?.query ?? ""
            recorder.record(RecordedRequest(line: "GET \(path)\(query.isEmpty ? "" : "?\(query)")", body: Data()))
            if path == "/api/v1/chat/c1/page", query == "before=u2" {
                return (200, Data(ChatPageFixture.page(Self.older, sources: Self.sources).utf8))
            }
            if path == "/api/v1/chat/c1/page" { return (200, Data(newest.utf8)) }
            if path.hasPrefix("/api/v1/chat/c1/messages/"), let row { return (200, Data(row.utf8)) }
            return (404, Data(envelope404.utf8))
        }
    }

    @Test("opens on the newest page and knows there is more")
    func opensOnNewestPage() async {
        let recorder = RequestRecorder()
        serve(recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        #expect(vm.messages.map(\.id) == ["u2", "a2"])
        #expect(vm.hasOlder)
        #expect(recorder.lines == ["GET /api/v1/chat/c1/page"])
    }

    @Test("a citation of a source found in a run not loaded still resolves")
    func citesUnloadedSources() async {
        serve(recorder: RequestRecorder())
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        guard case .assistantTurn(let turn) = vm.segments.last else {
            Issue.record("no turn")
            return
        }
        #expect(turn.citations.map(\.link) == ["https://a.example/"])
    }

    @Test("an older page goes in above, once, and the end of the history is known")
    func loadsOlderAbove() async {
        let recorder = RequestRecorder()
        serve(recorder: recorder)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        await vm.loadOlder()
        #expect(vm.messages.map(\.id) == ["u1", "a0", "t1", "a1", "u2", "a2"])
        #expect(!vm.hasOlder)
        #expect(vm.olderPageCount == 1)
        await vm.loadOlder()
        #expect(recorder.lines == ["GET /api/v1/chat/c1/page", "GET /api/v1/chat/c1/page?before=u2"])
        // The source is in a loaded run now, and still cited once.
        guard case .assistantTurn(let turn) = vm.segments.last else {
            Issue.record("no turn")
            return
        }
        #expect(turn.citations.map(\.link) == ["https://a.example/"])
    }

    @Test("a row cut to fit the page is replaced by the whole row")
    func fillsTruncatedRow() async throws {
        let cut = #"""
            [{"id":"u2","runId":"u2","role":"user","content":"q","createdAt":"2026-09-18T12:01:00.000Z"},
             {"id":"a2","runId":"u2","role":"assistant","content":[{"type":"text","text":"cut…"}],"stopReason":"stop","truncated":true,"createdAt":"2026-09-18T12:01:01.000Z"}]
            """#
        let whole =
            #"{"id":"a2","runId":"u2","role":"assistant","content":[{"type":"text","text":"the whole answer"}],"stopReason":"stop","createdAt":"2026-09-18T12:01:01.000Z"}"#
        serve(recorder: RequestRecorder(), newestPage: ChatPageFixture.page(cut), row: whole)
        let vm = Harness().makeViewModel()
        await vm.loadHistory()
        try await waitUntil("the whole row") {
            guard case .assistantTurn(let turn) = vm.segments.last else { return false }
            return turn.body == "the whole answer"
        }
    }
}
