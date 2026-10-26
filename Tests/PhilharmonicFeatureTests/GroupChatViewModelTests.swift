import ChatFeature
import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import PhilharmonicFeature

/// Its own protocol class: the handler is process-global, and other suites mock URL loading in parallel.
final class GroupMockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Seen: Sendable {
        let method: String
        let path: String
        let query: String?
        let body: Data
    }

    typealias Route = @Sendable (_ method: String, _ path: String, _ query: String?) -> (Int, String)

    static let route = Mutex<Route>({ _, _, _ in (200, "[]") })
    static let seen = Mutex<[Seen]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let query = request.url?.query
        Self.seen.withLock { $0.append(Seen(method: method, path: path, query: query, body: body)) }
        let (status, text) = Self.route.withLock { $0 }(method, path, query)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The group's stream, fed by the test: each connect opens a new one, and the test speaks into the newest.
private final class Wire: Sendable {
    typealias Item = SSEItem<PhilharmonicSseEvent>
    let connects = Mutex(0)
    private let open = Mutex<[AsyncThrowingStream<Item, Error>.Continuation]>([])

    var connect: GroupStream.Connect {
        { [self] in
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: Item.self)
            open.withLock { $0.append(continuation) }
            connects.withLock { $0 += 1 }
            return stream
        }
    }

    func send(_ items: Item...) { open.withLock { list in items.forEach { list.last?.yield($0) } } }
    func drop() { open.withLock { $0.last?.finish() } }
    func fail(_ error: Error) { open.withLock { $0.last?.finish(throwing: error) } }
}

private final class Flag: Sendable {
    private let state = Mutex(false)
    var isOn: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

/// The server's bodies.
private enum Body {
    static func row(_ id: String, role: String = "user", content: String = "hi") -> String {
        #"{"id":"\#(id)","conversationId":"c1","role":"\#(role)","agentId":null,"content":"\#(content)","parts":null,"taskId":null,"roundId":null,"createdAt":"2026-10-23T10:00:00.000Z"}"#
    }

    static let plan =
        #"{"id":"p1","conversationId":"c1","summary":"Ship it","status":"active","createdAt":"t","updatedAt":"t","steps":[]}"#
    static let group = #"{"id":"c1","title":"Atlas","createdAt":"t","updatedAt":"t","lastMessageAt":"t"}"#

    /// A group with one saved row and a plan.
    static let oneRow: GroupMockURLProtocol.Route = { _, path, _ in
        if path.hasSuffix("/plan") { return (200, plan) }
        if path.hasSuffix("/messages") { return (200, "[\(row("m1"))]") }
        if path.hasSuffix("/conversations") { return (200, "[\(group)]") }
        return (404, "{}")
    }
}

@MainActor
@Suite("GroupChatViewModel", .serialized)
struct GroupChatViewModelTests {
    private let wire = Wire()

    private func makeVM(_ route: @escaping GroupMockURLProtocol.Route) -> GroupChatViewModel {
        GroupMockURLProtocol.route.withLock { $0 = route }
        GroupMockURLProtocol.seen.withLock { $0.removeAll() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GroupMockURLProtocol.self]
        let store = ServerConfigStore(userDefaults: UserDefaults(suiteName: "GroupChatViewModelTests")!)
        let api = PhilharmonicAPI(
            client: APIClient(session: URLSession(configuration: config), serverConfig: store), serverConfig: store)
        let stream = GroupStream(connect: wire.connect, unlock: { false }, sleep: { _ in }, idleLimit: .seconds(3600))
        return GroupChatViewModel(conversationId: "c1", api: api, stream: stream)
    }

    private func requests(_ suffix: String, query: String? = nil) -> Int {
        GroupMockURLProtocol.seen.withLock { list in
            list.filter { $0.method == "GET" && $0.path.hasSuffix(suffix) && $0.query == query }.count
        }
    }

    private func afterReads() -> Int {
        GroupMockURLProtocol.seen.withLock { list in
            list.filter { $0.path.hasSuffix("/messages") && $0.query?.hasPrefix("after=") == true }.count
        }
    }

    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// URLSession hands over a stream's response only with its first byte, and a quiet group's first byte is the
    /// server's ping 15 s later: the group is read on open, not on the stream's.
    @Test func readsTheGroupBeforeTheStreamOpens() async {
        let vm = makeVM(Body.oneRow)
        await vm.start()
        await eventually { !vm.isLoading }
        #expect(vm.bubbles.map(\.id) == ["m1"])
        #expect(vm.plan?.summary == "Ship it")
        vm.stop()
    }

    private func started(_ vm: GroupChatViewModel) async {
        await vm.start()
        await eventually { wire.connects.withLock { $0 } == 1 }
        wire.send(.opened)
        // Read twice by then: on open, and on the stream's connect.
        await eventually { requests("/plan") == 2 }
    }

    @Test("opening a group reads its messages and plan once the stream is up")
    func startReadsMessagesAndPlan() async {
        let vm = makeVM(Body.oneRow)
        #expect(vm.isLoading)
        await started(vm)
        #expect(vm.bubbles.map(\.id) == ["m1"])
        #expect(vm.plan?.summary == "Ship it")
        #expect(vm.notice == nil)
        vm.stop()
    }

    @Test("a delta is the whole text so far: it replaces")
    func deltaReplacesText() async {
        let vm = makeVM(Body.oneRow)
        await started(vm)
        wire.send(
            .event(.messageStart(conversationId: "c1", messageId: "m2", role: .pm, agentId: nil)),
            .event(.messageDelta(conversationId: "c1", messageId: "m2", delta: "He")),
            .event(.messageDelta(conversationId: "c1", messageId: "m2", delta: "Hello")))
        await eventually { vm.bubbles.last?.text == "Hello" }
        #expect(vm.bubbles.map(\.id) == ["m1", "m2"])
        #expect(vm.bubbles.last?.isLive == true)
        vm.stop()
    }

    @Test("message_end reads only the rows after the last one held; a failed read reads the whole group")
    func afterReadDedupsAndFallsBack() async {
        let failAfter = Flag()
        let vm = makeVM { method, path, query in
            if path.hasSuffix("/plan") { return (200, "null") }
            if path.hasSuffix("/messages") {
                if query == nil {
                    return (200, failAfter.isOn ? "[\(Body.row("m1")),\(Body.row("m2")),\(Body.row("m3"))]" : "[\(Body.row("m1"))]")
                }
                return failAfter.isOn ? (500, "{}") : (200, "[\(Body.row("m2", role: "pm", content: "Done"))]")
            }
            return (404, "{}")
        }
        await started(vm)
        wire.send(
            .event(.messageStart(conversationId: "c1", messageId: "m2", role: .pm, agentId: nil)),
            .event(.messageEnd(conversationId: "c1", messageId: "m2")),
            .event(.messageEnd(conversationId: "c1", messageId: "m2")))
        await eventually { afterReads() >= 2 }
        await eventually { vm.bubbles.last?.isLive == false }
        #expect(vm.bubbles.map(\.id) == ["m1", "m2"])
        #expect(vm.bubbles.last?.text == "Done")

        failAfter.isOn = true
        wire.send(.event(.messageEnd(conversationId: "c1", messageId: "m3")))
        await eventually { vm.bubbles.count == 3 }
        #expect(vm.bubbles.map(\.id) == ["m1", "m2", "m3"])
        // Whole reads: on open, on the stream's connect, and the failed `after` read's fallback.
        #expect(requests("/messages") == 3)
        vm.stop()
    }

    @Test("every reconnect reads the messages and the plan whole again")
    func reconnectReadsWhole() async {
        let vm = makeVM(Body.oneRow)
        await started(vm)
        #expect(requests("/messages") == 2)
        wire.drop()
        await eventually { wire.connects.withLock { $0 } == 2 }
        wire.send(.opened)
        await eventually { requests("/plan") == 3 }
        #expect(requests("/messages") == 3)
        vm.stop()
    }

    @Test("a group deleted elsewhere says so and stops listening")
    func deletedGroupStopsAndReports() async {
        let vm = makeVM { _, path, _ in
            if path.hasSuffix("/plan") { return (200, "null") }
            // The server answers an unknown group's messages with an empty list, and leaves it out of the list.
            return (200, "[]")
        }
        // The read on open finds it gone, before the stream has said anything.
        await vm.start()
        await eventually { vm.notice != nil }
        #expect(vm.notice == .gone)
        wire.drop()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(wire.connects.withLock { $0 } == 1)
    }

    @Test("a group with no messages yet is not gone")
    func emptyGroupIsNotGone() async {
        let vm = makeVM { _, path, _ in
            if path.hasSuffix("/plan") { return (200, "null") }
            if path.hasSuffix("/conversations") { return (200, "[\(Body.group)]") }
            return (200, "[]")
        }
        await started(vm)
        // Each whole read of an empty group asks the list: on open and on the stream's connect.
        await eventually { requests("/conversations") == 2 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(vm.notice == nil)
        #expect(vm.bubbles.isEmpty)
        vm.stop()
    }

    @Test("a prompt answered elsewhere settles without an error")
    func promptGoneSettlesQuietly() async {
        let vm = makeVM { _, _, _ in
            (409, #"{"type":"error","error":{"code":"AGENT_PROMPT_GONE","message":"That prompt was already answered"}}"#)
        }
        await vm.respond(card: Fx.card(state: .blocked, prompts: [Fx.prompt]), prompt: Fx.prompt, answer: .allow)
        #expect(vm.notice == nil)
        #expect(vm.settledPrompts.contains("r1"))
        let seen = GroupMockURLProtocol.seen.withLock { $0.last }
        #expect(seen?.path == "/api/v1/agents/sessions/s1/respond")
    }

    @Test("photos go as data URLs, and the sent row shows at once")
    func sendPostsDataURLs() async throws {
        let vm = makeVM { method, _, _ in method == "POST" ? (201, Body.row("m5", content: "look")) : (200, "[]") }
        let picture = ComposerPicture(
            mimeType: "image/jpeg", dataURL: "data:image/jpeg;base64,AA", pixelWidth: 1, pixelHeight: 1)
        let sent = await vm.send(text: "look", pictures: [picture])
        #expect(sent)
        let seen = try #require(GroupMockURLProtocol.seen.withLock { $0.last })
        #expect(seen.path == "/api/v1/philharmonic/conversations/c1/messages")
        let body = try JSONDecoder().decode([String: JSONValue].self, from: seen.body)
        #expect(body["content"] == .string("look"))
        #expect(
            body["attachments"]
                == .array([
                    .object([
                        "name": .string("photo-1.jpg"), "url": .string("data:image/jpeg;base64,AA"),
                        "contentType": .string("image/jpeg"),
                    ])
                ]))
        #expect(vm.bubbles.map(\.id) == ["m5"])
    }

    @Test("the PM's question stays until its round ends")
    func askUserClearsOnPmEnded() async {
        let vm = makeVM(Body.oneRow)
        await started(vm)
        wire.send(
            .event(.pmStarted(conversationId: "c1")),
            .event(.askUser(conversationId: "c1", question: "Which?", options: ["A", "B"])))
        await eventually { vm.askUser != nil }
        #expect(vm.askUser == GroupQuestion(question: "Which?", options: ["A", "B"]))
        #expect(vm.pmRunning)
        #expect(vm.busy.label(for: BusyAgents.pm) == .orchestrating)
        wire.send(.event(.pmEnded(conversationId: "c1", reason: "done")))
        await eventually { !vm.pmRunning }
        #expect(vm.askUser == nil)
        vm.stop()
    }

    @Test("another group's events are not this group's")
    func otherConversationEventsIgnored() async {
        let vm = makeVM(Body.oneRow)
        await started(vm)
        wire.send(
            .event(.pmStarted(conversationId: "c2")),
            .event(.messageStart(conversationId: "c2", messageId: "x", role: .pm, agentId: nil)),
            .event(.conversationError(conversationId: "c2", error: "boom")),
            .event(.messageStart(conversationId: "c1", messageId: "m2", role: .pm, agentId: nil)))
        await eventually { vm.bubbles.count == 2 }
        #expect(vm.bubbles.map(\.id) == ["m1", "m2"])
        #expect(!vm.pmRunning)
        #expect(vm.notice == nil)
        vm.stop()
    }

    // MARK: Final review fixes

    @Test("a reconnect forgets the round state it held: the server re-sends what is still true")
    func reconnectClearsStaleRoundState() async {
        let vm = makeVM(Body.oneRow)
        await started(vm)
        wire.send(
            .event(.pmStarted(conversationId: "c1")),
            .event(.askUser(conversationId: "c1", question: "Which?", options: ["A"])))
        await eventually { vm.askUser != nil }
        // The round ended while the app was away: no pm_ended reaches the phone.
        wire.drop()
        await eventually { wire.connects.withLock { $0 } == 2 }
        wire.send(.opened)
        await eventually { requests("/plan") == 3 }
        #expect(!vm.pmRunning)
        #expect(vm.askUser == nil)
        #expect(vm.busy.label(for: BusyAgents.pm) == nil)
        vm.stop()
    }

    @Test("a new message closes the PM's question, as on the desktop (answered there)")
    func messageStartClearsQuestion() async {
        let vm = makeVM(Body.oneRow)
        await started(vm)
        wire.send(.event(.askUser(conversationId: "c1", question: "Which?", options: ["A"])))
        await eventually { vm.askUser != nil }
        wire.send(.event(.messageStart(conversationId: "c1", messageId: "m2", role: .user, agentId: nil)))
        await eventually { vm.askUser == nil }
        #expect(vm.askUser == nil)
        vm.stop()
    }

    @Test("back in the foreground the group is read whole at once, not at the stream's first byte")
    func resumeReadsWholeAtOnce() async {
        let vm = makeVM(Body.oneRow)
        await started(vm)
        #expect(requests("/messages") == 2)
        await vm.resume()
        await eventually { requests("/messages") == 3 }
        #expect(requests("/messages") == 3)
        vm.stop()
    }

    @Test("an error notice goes once a read succeeds")
    func errorNoticeClearsOnSuccessfulRead() async {
        let failing = Flag()
        failing.isOn = true
        let vm = makeVM { _, path, _ in
            if failing.isOn { return (500, #"{"error":{"code":"X","message":"no"}}"#) }
            return Body.oneRow("GET", path, nil)
        }
        await vm.start()
        await eventually { vm.notice != nil }
        #expect(vm.notice != nil)
        failing.isOn = false
        wire.send(.opened)
        await eventually { vm.notice == nil }
        #expect(vm.notice == nil)
        vm.stop()
    }

    @Test("a send that fails because the group was deleted says the group is gone")
    func failedSendToDeletedGroupIsGone() async {
        let vm = makeVM { method, path, _ in
            if method == "POST" { return (500, #"{"error":{"code":"DB","message":"foreign key"}}"#) }
            if path.hasSuffix("/conversations") { return (200, "[]") }
            return (200, "[]")
        }
        let sent = await vm.send(text: "hi", pictures: [])
        #expect(!sent)
        #expect(vm.notice == .gone)
    }

    @Test("locked, then back in the foreground: the group tries again")
    func lockedResumeStartsAgain() async {
        let vm = makeVM(Body.oneRow)
        await started(vm)
        wire.fail(HTTPError(statusCode: 423, code: "APP_LOCKED", message: "Locked"))
        await eventually { vm.notice == .locked }
        #expect(vm.notice == .locked)
        await vm.resume()
        await eventually { wire.connects.withLock { $0 } == 2 }
        #expect(wire.connects.withLock { $0 } == 2)
        await eventually { vm.notice == nil }
        #expect(vm.notice == nil)
        vm.stop()
    }
}
