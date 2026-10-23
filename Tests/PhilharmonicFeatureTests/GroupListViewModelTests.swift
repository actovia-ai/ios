import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import PhilharmonicFeature

/// Its own protocol class: `GroupMockURLProtocol`'s route belongs to the view model's suite, which runs beside this one.
final class ListMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Route = @Sendable (_ method: String, _ path: String) -> (Int, String)

    static let route = Mutex<Route>({ _, _ in (200, "[]") })
    static let methods = Mutex<[String]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        Self.methods.withLock { $0.append("\(method) \(request.url?.path ?? "")") }
        let (status, text) = Self.route.withLock { $0 }(method, request.url?.path ?? "")
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private enum Groups {
    static func json(_ id: String, title: String = "G", lastMessageAt: String) -> String {
        #"{"id":"\#(id)","title":"\#(title)","icon":null,"createdAt":"2026-10-01T00:00:00.000Z","updatedAt":"2026-10-01T00:00:00.000Z","lastMessageAt":"\#(lastMessageAt)"}"#
    }

    static let three =
        "[\(json("old", lastMessageAt: "2026-10-01T09:00:00.000Z")),\(json("new", lastMessageAt: "2026-10-23T09:00:00.000Z")),\(json("mid", lastMessageAt: "2026-10-10T09:00:00.000Z"))]"
}

@MainActor
@Suite("GroupListViewModel", .serialized)
struct GroupListViewModelTests {
    private func makeModel(_ route: @escaping ListMockURLProtocol.Route) -> GroupListViewModel {
        ListMockURLProtocol.route.withLock { $0 = route }
        ListMockURLProtocol.methods.withLock { $0.removeAll() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ListMockURLProtocol.self]
        let store = ServerConfigStore(userDefaults: UserDefaults(suiteName: "GroupListViewModelTests")!)
        let api = PhilharmonicAPI(
            client: APIClient(session: URLSession(configuration: config), serverConfig: store), serverConfig: store)
        return GroupListViewModel(api: api)
    }

    @Test("groups are listed newest message first")
    func loadSortsByLastMessage() async {
        let model = makeModel { _, _ in (200, Groups.three) }
        await model.load()
        #expect(model.groups.map(\.id) == ["new", "mid", "old"])
        #expect(model.errorMessage == nil)
    }

    @Test("a delete the server refused puts the group back where it was")
    func deleteRollsBackOnFailure() async {
        let model = makeModel { method, _ in method == "DELETE" ? (500, "{}") : (200, Groups.three) }
        await model.load()
        let mid = model.groups[1]
        let deleted = await model.delete(mid)
        #expect(!deleted)
        #expect(model.groups.map(\.id) == ["new", "mid", "old"])
        #expect(model.errorMessage != nil)
        #expect(ListMockURLProtocol.methods.withLock { $0 }.contains("DELETE /api/v1/philharmonic/conversations/mid"))
    }

    @Test("a deleted group leaves the list")
    func deleteRemoves() async {
        let model = makeModel { method, _ in method == "DELETE" ? (200, #"{"success":true}"#) : (200, Groups.three) }
        await model.load()
        #expect(await model.delete(model.groups[0]))
        #expect(model.groups.map(\.id) == ["mid", "old"])
    }

    @Test("a new group goes to the top")
    func createInsertsAtTop() async {
        let model = makeModel { method, _ in
            method == "POST"
                ? (201, Groups.json("fresh", title: "Launch", lastMessageAt: "2026-10-23T12:00:00.000Z"))
                : (200, Groups.three)
        }
        await model.load()
        let created = await model.create(title: "Launch", icon: "🚀")
        #expect(created?.id == "fresh")
        #expect(model.groups.first?.id == "fresh")
        #expect(model.groups.count == 4)
    }

    @Test("a rename shows at once and stays when the server agrees")
    func renameUpdatesTitle() async {
        let model = makeModel { method, _ in
            method == "PUT"
                ? (200, Groups.json("mid", title: "Renamed", lastMessageAt: "2026-10-10T09:00:00.000Z"))
                : (200, Groups.three)
        }
        await model.load()
        #expect(await model.rename(model.groups[1], title: "Renamed"))
        #expect(model.groups[1].title == "Renamed")
    }
}
