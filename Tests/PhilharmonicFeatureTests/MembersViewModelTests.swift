import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import PhilharmonicFeature

/// Its own protocol class: the handler is process-global, and other suites mock URL loading in parallel.
final class MembersMockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Route = @Sendable (_ path: String) -> (Int, String)
    static let route = Mutex<Route>({ _ in (200, "[]") })
    static let paths = Mutex<[String]>([])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.paths.withLock { $0.append(path) }
        let (status, text) = Self.route.withLock { $0 }(path)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The sleeps the model asked for; the first returns at once, every later one waits until cancelled.
private final class Sleeps: Sendable {
    let asked = Mutex<[Duration]>([])

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in
            let count = asked.withLock { list in
                list.append(duration)
                return list.count
            }
            if count > 1 { try await Task.sleep(for: .seconds(3600)) }
        }
    }
}

private enum Body {
    static let employees =
        #"[{"id":"a1","name":"Kai","teamId":null,"runtime":"claude-code","model":"opus"},{"id":"a2","name":"Nora","teamId":null,"runtime":"actovia"},{"id":"a3","name":"Rin","teamId":null,"runtime":"codex"}]"#
    static let groups =
        #"[{"id":"c1","title":"Atlas","createdAt":"t","updatedAt":"t","lastMessageAt":"t","memberAgentIds":["a3","a1"]}]"#
    /// Claude Code stopped on its 5-hour window, which resets at 2026-10-23 12:00 UTC.
    static let quota =
        #"[{"cli":"claude-code","windows":[{"name":"five_hour","usedPercent":100,"resetsAt":1792756800000,"rejected":true},{"name":"seven_day","usedPercent":41.6,"resetsAt":1793000000000}],"state":"rejected","rejectedWindow":"five_hour","overage":false,"asOf":1792750000000}]"#
}

@MainActor
@Suite("MembersViewModel", .serialized)
struct MembersViewModelTests {
    private let sleeps = Sleeps()

    private func makeVM(
        memberIds: [String]? = ["a1", "a2"], conversationId: String? = nil,
        sleep: (@Sendable (Duration) async throws -> Void)? = nil
    ) -> MembersViewModel {
        MembersMockURLProtocol.route.withLock {
            $0 = { path in
                if path.hasSuffix("/agents/quota") { return (200, Body.quota) }
                if path.hasSuffix("/agents") { return (200, Body.employees) }
                if path.hasSuffix("/conversations") { return (200, Body.groups) }
                return (404, "{}")
            }
        }
        MembersMockURLProtocol.paths.withLock { $0.removeAll() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MembersMockURLProtocol.self]
        let store = ServerConfigStore(userDefaults: UserDefaults(suiteName: "MembersViewModelTests")!)
        let api = PhilharmonicAPI(
            client: APIClient(session: URLSession(configuration: config), serverConfig: store), serverConfig: store)
        return MembersViewModel(
            api: api, memberIds: memberIds, conversationId: conversationId, sleep: sleep ?? sleeps.sleep)
    }

    private func quotaReads() -> Int {
        MembersMockURLProtocol.paths.withLock { $0.filter { $0.hasSuffix("/agents/quota") }.count }
    }

    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func quotaReReadsEveryMinuteWhileOpen() async {
        let vm = makeVM()
        vm.start()
        await eventually { quotaReads() == 2 && sleeps.asked.withLock { $0.count } == 2 }
        #expect(quotaReads() == 2)
        #expect(sleeps.asked.withLock { $0 } == [.seconds(60), .seconds(60)])
        vm.stop()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(quotaReads() == 2)
    }

    @Test func membersAreTheGroupsOnly() async {
        let vm = makeVM(memberIds: ["a2", "a1"])
        vm.start()
        await eventually { vm.members.count == 2 }
        #expect(vm.members.map(\.id) == ["a2", "a1"])
        vm.stop()
    }

    @Test func quotaLineSaysLimitReached() async throws {
        let vm = makeVM()
        vm.start()
        await eventually { vm.members.count == 2 && !vm.quotas.isEmpty }
        vm.stop()
        let kai = try #require(vm.members.first { $0.id == "a1" })
        let line = try #require(vm.quotaLine(for: kai, now: Date(timeIntervalSince1970: 1_792_750_000)))
        #expect(line.isLimited)
        #expect(line.text.hasPrefix("5h 100% · week 42% · limit reached · resets "))
        // Actovia's own loop has no quota, and a CLI that reported none has no line.
        let nora = try #require(vm.members.first { $0.id == "a2" })
        #expect(vm.quotaLine(for: nora, now: .now) == nil)
        #expect(vm.quotaLine(for: Employee(id: "a3", name: "Rin", runtime: "codex"), now: .now) == nil)
    }

    @Test func aResetLimitIsNotRed() async throws {
        let vm = makeVM()
        vm.start()
        await eventually { vm.members.count == 2 && !vm.quotas.isEmpty }
        vm.stop()
        let kai = try #require(vm.members.first { $0.id == "a1" })
        let line = try #require(vm.quotaLine(for: kai, now: Date(timeIntervalSince1970: 1_792_760_000)))
        #expect(!line.isLimited)
        #expect(line.text == "5h 100% · week 42%")
    }

    @Test("opened before the screen had the group's members, the sheet reads them itself (ISSUE-249 M3)")
    func readsTheGroupWhenNotGivenMembers() async {
        let vm = makeVM(memberIds: nil, conversationId: "c1")
        vm.start()
        await eventually { vm.hasLoaded }
        #expect(vm.members.map(\.id) == ["a3", "a1"])
        vm.stop()
    }

    @Test("dropped without stop(), the model goes and its quota loop ends (ISSUE-249 M1)")
    func loopEndsWithTheModel() async {
        weak var gone: MembersViewModel?
        do {
            let vm = makeVM(sleep: { _ in try await Task.sleep(for: .milliseconds(10)) })
            gone = vm
            vm.start()
            await eventually { quotaReads() >= 2 }
        }
        await eventually { gone == nil }
        #expect(gone == nil)
        let reads = quotaReads()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(quotaReads() == reads)
    }
}
