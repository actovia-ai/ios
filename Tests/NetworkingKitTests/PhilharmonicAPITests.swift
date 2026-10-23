import Foundation
import Models
import Synchronization
import Testing

@testable import NetworkingKit

/// Its own protocol class and recorder: other suites set `MockURLProtocol.handler` in parallel.
final class PhilMockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Seen: Sendable {
        let method: String?
        let url: URL?
        let body: Data
    }

    nonisolated(unsafe) static var answer: (status: Int, body: String) = (200, "{}")
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
        let entry = Seen(method: request.httpMethod, url: request.url, body: body)
        Self.seen.withLock { $0.append(entry) }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.answer.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("PhilharmonicAPI", .serialized)
struct PhilharmonicAPITests {
    private func makeAPI(status: Int = 200, body: String) -> PhilharmonicAPI {
        PhilMockURLProtocol.answer = (status, body)
        PhilMockURLProtocol.seen.withLock { $0.removeAll() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PhilMockURLProtocol.self]
        let store = ServerConfigStore(userDefaults: UserDefaults(suiteName: "PhilharmonicAPITests")!)
        return PhilharmonicAPI(
            client: APIClient(session: URLSession(configuration: config), serverConfig: store), serverConfig: store)
    }

    private var last: PhilMockURLProtocol.Seen? { PhilMockURLProtocol.seen.withLock { $0.last } }

    private let message = #"""
        {"id":"m10","conversationId":"c1","role":"user","agentId":null,"content":"hi","parts":null,"taskId":null,"roundId":null,"createdAt":"t"}
        """#

    @Test("messages(after:) asks for the rows after that one")
    func messagesAfterSendsQuery() async throws {
        let api = makeAPI(body: "[\(message)]")
        let rows = try await api.messages(conversationId: "c1", after: "m9")
        #expect(rows.map(\.id) == ["m10"])
        let url = try #require(last?.url)
        #expect(url.path == "/api/v1/philharmonic/conversations/c1/messages")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "after", value: "m9")])
        _ = try await api.messages(conversationId: "c1")
        #expect(last?.url?.query == nil)
    }

    @Test("send posts the text and the photos as data URLs")
    func sendPostsDataURLAttachments() async throws {
        let api = makeAPI(status: 201, body: message)
        let sent = try await api.send(
            conversationId: "c1", content: "hi",
            attachments: [OutgoingAttachment(name: "a.jpg", url: "data:image/jpeg;base64,AA", contentType: "image/jpeg")])
        #expect(sent.id == "m10")
        let seen = try #require(last)
        #expect(seen.method == "POST")
        #expect(seen.url?.path == "/api/v1/philharmonic/conversations/c1/messages")
        let body = try JSONDecoder().decode([String: JSONValue].self, from: seen.body)
        #expect(body["content"] == .string("hi"))
        #expect(
            body["attachments"]
                == .array([
                    .object([
                        "name": .string("a.jpg"), "url": .string("data:image/jpeg;base64,AA"),
                        "contentType": .string("image/jpeg"),
                    ])
                ]))
    }

    @Test("a prompt answered elsewhere is gone, not an error; any other failure throws")
    func respondMapsGoneTo409() async throws {
        let gone = makeAPI(
            status: 409, body: #"{"type":"error","error":{"code":"AGENT_PROMPT_GONE","message":"That prompt was already answered"}}"#)
        #expect(try await gone.respond(sessionId: "s1", requestId: "r1", answer: .allow) == .gone)
        let seen = try #require(last)
        #expect(seen.url?.path == "/api/v1/agents/sessions/s1/respond")
        let body = try JSONDecoder().decode([String: JSONValue].self, from: seen.body)
        #expect(body["requestId"] == .string("r1"))
        #expect(body["answer"] == .object(["kind": .string("allow")]))

        let done = makeAPI(body: #"{"success":true}"#)
        #expect(try await done.respond(sessionId: "s1", requestId: "r1", answer: .deny(reason: nil)) == .done)

        let broken = makeAPI(status: 500, body: #"{"type":"error","error":{"code":"INTERNAL_ERROR","message":"boom"}}"#)
        await #expect(throws: HTTPError.self) {
            _ = try await broken.respond(sessionId: "s1", requestId: "r1", answer: .allow)
        }
    }

    @Test("the dashboard's costs are the last thirty days")
    func costsAskForThirtyDays() async throws {
        let api = makeAPI(body: #"{"totalCost":0,"totalTokens":0,"byConversation":[],"byAgent":[],"daily":[]}"#)
        _ = try await api.costs(days: 30)
        let url = try #require(last?.url)
        #expect(url.path == "/api/v1/philharmonic/costs")
        #expect(url.query == "days=30")
    }

    @Test("interrupt says whether a round was running")
    func interruptReportsWasRunning() async throws {
        let api = makeAPI(body: #"{"success":true,"wasRunning":true}"#)
        #expect(try await api.interrupt(conversationId: "c1"))
        #expect(last?.url?.path == "/api/v1/philharmonic/conversations/c1/interrupt")
    }

    @Test("a group with no active plan has none")
    func noPlanIsNil() async throws {
        let api = makeAPI(body: "null")
        #expect(try await api.plan(conversationId: "c1") == nil)
    }

    @Test("cancelling a task patches its status")
    func cancelTaskPatches() async throws {
        let api = makeAPI(
            body: #"{"id":"k1","conversationId":"c1","title":"Nightly","description":null,"status":"cancelled","priority":"medium","assignedAgentId":null,"cronExpression":"0 3 * * *","runAt":null,"lastRunAt":null,"lastRunStatus":null,"createdAt":"t"}"#
        )
        let task = try await api.cancelTask(id: "k1")
        #expect(task.status == "cancelled")
        let seen = try #require(last)
        #expect(seen.method == "PATCH")
        #expect(seen.url?.path == "/api/v1/philharmonic/tasks/k1")
        #expect(try JSONDecoder().decode([String: String].self, from: seen.body) == ["status": "cancelled"])
    }

    @Test("the stream request carries the token and waits an hour")
    func streamRequestCarriesAuthorization() throws {
        let route = ServerRoute(
            bases: ["https://computer.test:63129"], authorization: "Bearer T", session: nil, fingerprint: nil)
        let request = try #require(PhilharmonicAPI.streamRequest(conversationId: "c1", route: route))
        #expect(request.url?.absoluteString == "https://computer.test:63129/api/v1/philharmonic/conversations/c1/sse")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer T")
        #expect(request.timeoutInterval == 3600)
        #expect(request.httpMethod == "GET")
        let none = ServerRoute(bases: [], authorization: nil, session: nil, fingerprint: nil)
        #expect(PhilharmonicAPI.streamRequest(conversationId: "c1", route: none) == nil)
    }
}
