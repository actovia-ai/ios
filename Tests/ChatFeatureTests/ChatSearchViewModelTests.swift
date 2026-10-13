import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import ChatFeature

// MARK: - Test doubles

/// Answers immediately from a script (then with no hits), recording every query it saw.
private actor RecordingService: ChatSearchService {
    private(set) var queries: [String] = []
    private var script: [Result<[ChatSearchResult], Error>]

    init(script: [Result<[ChatSearchResult], Error>] = []) { self.script = script }

    func search(query: String) async throws -> [ChatSearchResult] {
        queries.append(query)
        if script.isEmpty { return [] }
        return try script.removeFirst().get()
    }
}

/// Holds every request open until the test completes it, so responses can arrive out of order.
private actor ControlledService: ChatSearchService {
    private(set) var queries: [String] = []
    private var pending: [String: CheckedContinuation<[ChatSearchResult], Error>] = [:]

    func search(query: String) async throws -> [ChatSearchResult] {
        queries.append(query)
        return try await withCheckedThrowingContinuation { pending[query] = $0 }
    }

    func complete(_ query: String, with results: [ChatSearchResult]) {
        pending.removeValue(forKey: query)?.resume(returning: results)
    }
}

private func result(_ chatId: String, title: String = "T", snippet: String? = "some text") -> ChatSearchResult {
    ChatSearchResult(
        chatId: chatId, title: title, matchedAt: "2026-10-14T08:00:00.000Z",
        snippets: snippet.map {
            [ChatSearchSnippet(messageId: "m-\(chatId)", role: "assistant", text: $0, createdAt: "2026-10-14T08:00:00.000Z")]
        } ?? [])
}

/// Polls (bounded) until `condition` holds, so a broken build fails instead of hanging.
@MainActor
private func waitUntil(
    _ what: String, timeout: Duration = .seconds(5), _ condition: @MainActor () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !(await condition()) {
        try #require(ContinuousClock.now < deadline, "timed out waiting for \(what)")
        try await Task.sleep(for: .milliseconds(2))
    }
}

private final class SearchMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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
        config.protocolClasses = [SearchMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

// MARK: - Tests

@MainActor
@Suite("ChatSearchViewModel", .serialized)
struct ChatSearchViewModelTests {
    @Test("a blank query issues no request and stays idle")
    func blankQueryDoesNotSearch() async throws {
        let service = RecordingService()
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(5))
        vm.updateQuery("   ")
        try await Task.sleep(for: .milliseconds(60))
        #expect(await service.queries.isEmpty)
        #expect(vm.phase == .idle)
        #expect(vm.isSearching == false)
        #expect(vm.hasQuery == false)
    }

    @Test("rapid edits are coalesced into one request for the last text")
    func debounceCoalescesEdits() async throws {
        let service = RecordingService()
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(40))
        vm.updateQuery("a")
        vm.updateQuery("ab")
        vm.updateQuery("abc")
        try await waitUntil("the search to finish") { vm.phase != .idle }
        #expect(await service.queries == ["abc"])
        #expect(vm.phase == .empty)
        #expect(vm.isSearching == false)
    }

    @Test("the server's results are shown as they came, in order")
    func showsTheServersResults() async throws {
        let results = [result("c1", title: "One"), result("c2", title: "Two", snippet: nil)]
        let service = RecordingService(script: [.success(results)])
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(1))
        vm.updateQuery("needle")
        try await waitUntil("results") { vm.phase != .idle }
        #expect(vm.phase == .results(results))
    }

    @Test("a failure is shown as failed(message) and retry() runs the same query again")
    func failureThenRetry() async throws {
        let service = RecordingService(script: [
            .failure(HTTPError(statusCode: 500, code: "X", message: "boom")),
            .success([result("c1", title: "One")]),
        ])
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(1))
        vm.updateQuery("q")
        try await waitUntil("the failure") { vm.phase != .idle }
        #expect(vm.phase == .failed("boom"))
        #expect(vm.isSearching == false)

        vm.retry()
        try await waitUntil("the retry") { vm.phase != .failed("boom") }
        #expect(vm.phase == .results([result("c1", title: "One")]))
        #expect(await service.queries == ["q", "q"])
    }

    @Test("a response that arrives after a newer query started is dropped")
    func staleResponseIsDropped() async throws {
        let service = ControlledService()
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(1))
        vm.updateQuery("first")
        try await waitUntil("the first request") { await service.queries == ["first"] }
        vm.updateQuery("second")
        try await waitUntil("the second request") { await service.queries == ["first", "second"] }

        await service.complete("second", with: [result("c2", title: "Second")])
        try await waitUntil("the second results") { vm.phase != .idle }
        await service.complete("first", with: [result("c1", title: "First")])
        try await Task.sleep(for: .milliseconds(50))

        #expect(vm.phase == .results([result("c2", title: "Second")]))
        #expect(vm.isSearching == false)
    }

    @Test("reset() clears the query and results, and a response that arrives afterwards is ignored")
    func resetClearsEverything() async throws {
        let service = ControlledService()
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(1))
        vm.updateQuery("q")
        try await waitUntil("the request") { await service.queries == ["q"] }
        #expect(vm.isSearching)

        vm.reset()
        #expect(vm.query == "")
        #expect(vm.phase == .idle)
        #expect(vm.isSearching == false)

        await service.complete("q", with: [result("c1")])
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.phase == .idle)
    }

    @Test("a cancellation is not shown as a failure")
    func cancellationIsNotAFailure() async throws {
        let service = RecordingService(script: [.failure(CancellationError())])
        let vm = ChatSearchViewModel(service: service, debounce: .milliseconds(1))
        vm.updateQuery("q")
        try await waitUntil("the request to finish") {
            let searched = await !service.queries.isEmpty
            return vm.isSearching == false && searched
        }
        #expect(vm.phase == .idle)
    }

    @Test("hasQuery ignores surrounding whitespace")
    func hasQueryTrims() {
        let vm = ChatSearchViewModel(service: RecordingService(), debounce: .milliseconds(1))
        #expect(vm.hasQuery == false)
        vm.updateQuery("  x ")
        #expect(vm.hasQuery)
        vm.reset()
    }

    @Test("APIChatSearchService calls GET /api/v1/chat/search with the query encoded and decodes the chats")
    func apiServiceUsesTheRightEndpoint() async throws {
        let seen = Mutex<URL?>(nil)
        let rows = #"""
            [{"chatId":"c1","title":"Greeting","matchedAt":"2026-10-14T08:00:00.000Z",
              "snippets":[{"messageId":"m1","role":"user","text":"hi there","createdAt":"2026-10-14T08:00:00.000Z"}]}]
            """#
        SearchMockURLProtocol.handler = { request in
            seen.withLock { $0 = request.url }
            return (200, Data(rows.utf8))
        }
        let suite = "ChatSearchViewModelTests.apiService"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let client = APIClient(
            session: SearchMockURLProtocol.makeSession(), serverConfig: ServerConfigStore(userDefaults: defaults))

        let results = try await APIChatSearchService(apiClient: client).search(query: "c++ tips")

        let url = try #require(seen.withLock { $0 })
        #expect(url.path == "/api/v1/chat/search")
        #expect(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                == [URLQueryItem(name: "query", value: "c++ tips")])
        #expect(results.map(\.chatId) == ["c1"])
        #expect(results.first?.snippets.first?.text == "hi there")
    }
}
