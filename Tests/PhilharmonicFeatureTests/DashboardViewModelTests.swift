import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import PhilharmonicFeature

/// Its own protocol class: the handler is process-global, and other suites mock URL loading in parallel.
final class DashboardMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Route = @Sendable (_ method: String, _ path: String) -> (Int, String)
    static let route = Mutex<Route>({ _, _ in (200, "[]") })
    static let seen = Mutex<[(method: String, path: String, query: String?)]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        Self.seen.withLock { $0.append((method, path, request.url?.query)) }
        let (status, text) = Self.route.withLock { $0 }(method, path)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private enum Body {
    static let costs =
        #"{"totalCost":1.5,"totalTokens":1200,"byConversation":[{"conversationId":"c1","cost":1.5,"tokens":1200}],"byAgent":[{"agentId":"a1","cost":1.0,"tokens":800},{"agentId":"a2","cost":0.5,"tokens":400}],"daily":[]}"#

    static func task(_ id: String, cron: String? = nil, runAt: String? = nil) -> String {
        let cronValue = cron.map { "\"\($0)\"" } ?? "null"
        let runAtValue = runAt.map { "\"\($0)\"" } ?? "null"
        return #"{"id":"\#(id)","conversationId":"c1","title":"Task \#(id)","description":null,"status":"pending","priority":"medium","assignedAgentId":null,"cronExpression":\#(cronValue),"runAt":\#(runAtValue),"lastRunAt":null,"lastRunStatus":null,"createdAt":"t"}"#
    }
}

@MainActor
@Suite("DashboardViewModel", .serialized)
struct DashboardViewModelTests {
    private func makeVM(cancelFails: Bool = false) -> DashboardViewModel {
        DashboardMockURLProtocol.route.withLock {
            $0 = { method, path in
                if method == "PATCH" {
                    return cancelFails ? (500, #"{"error":{"code":"X","message":"no"}}"#) : (200, Body.task("k1"))
                }
                if path.hasSuffix("/costs") { return (200, Body.costs) }
                if path.hasSuffix("/tasks/upcoming") { return (200, "[\(Body.task("k1", runAt: "2026-10-24T09:00:00.000Z"))]") }
                if path.hasSuffix("/tasks/recurring") { return (200, "[\(Body.task("k2", cron: "0 3 * * *"))]") }
                if path.hasSuffix("/agents") { return (200, "[]") }
                return (404, "{}")
            }
        }
        DashboardMockURLProtocol.seen.withLock { $0.removeAll() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DashboardMockURLProtocol.self]
        let store = ServerConfigStore(userDefaults: UserDefaults(suiteName: "DashboardViewModelTests")!)
        let api = PhilharmonicAPI(
            client: APIClient(session: URLSession(configuration: config), serverConfig: store), serverConfig: store)
        return DashboardViewModel(api: api)
    }

    @Test func costsAreThirtyDays() async {
        let vm = makeVM()
        await vm.load()
        let query = DashboardMockURLProtocol.seen.withLock { $0.first { $0.path.hasSuffix("/costs") }?.query }
        #expect(query == "days=30")
        #expect(vm.costs?.totalCost == 1.5)
        #expect(vm.upcoming.map(\.id) == ["k1"])
        #expect(vm.recurring.map(\.id) == ["k2"])
    }

    @Test func cancelRemovesTheTask() async throws {
        let vm = makeVM()
        await vm.load()
        let task = try #require(vm.upcoming.first)
        await vm.cancel(task)
        #expect(vm.upcoming.isEmpty)
        #expect(DashboardMockURLProtocol.seen.withLock { $0.contains { $0.method == "PATCH" && $0.path.hasSuffix("/tasks/k1") } })
    }

    @Test func cancelRollsBackOnFailure() async throws {
        let vm = makeVM(cancelFails: true)
        await vm.load()
        let task = try #require(vm.recurring.first)
        await vm.cancel(task)
        #expect(vm.recurring.map(\.id) == ["k2"])
        #expect(vm.errorMessage != nil)
    }
}
