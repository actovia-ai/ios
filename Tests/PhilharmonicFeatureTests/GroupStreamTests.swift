import Foundation
import Models
import NetworkingKit
import Synchronization
import Testing

@testable import PhilharmonicFeature

/// A scripted server: each connect takes the next script (the last one repeats).
private final class FakeServer: Sendable {
    enum Script: Sendable {
        /// Fails before anything arrives.
        case fail(HTTPError?)
        /// Opens, sends these, then drops.
        case items([SSEItem<PhilharmonicSseEvent>])
        /// Opens and then says nothing, ever.
        case silent
    }

    private let scripts: [Script]
    let connects = Mutex(0)
    let sleeps = Mutex<[Duration]>([])

    init(_ scripts: [Script]) { self.scripts = scripts }

    func connect() -> AsyncThrowingStream<SSEItem<PhilharmonicSseEvent>, Error> {
        let n = connects.withLock { count in
            count += 1
            return count - 1
        }
        let script = scripts[min(n, scripts.count - 1)]
        return AsyncThrowingStream { continuation in
            switch script {
            case .fail(let error):
                continuation.finish(throwing: error ?? URLError(.networkConnectionLost))
            case .items(let items):
                continuation.yield(.opened)
                for item in items { continuation.yield(item) }
                continuation.finish(throwing: URLError(.networkConnectionLost))
            case .silent:
                continuation.yield(.opened)
            }
        }
    }

    var connectCount: Int { connects.withLock { $0 } }
    var slept: [Duration] { sleeps.withLock { $0 } }
}

private let notFound = HTTPError(statusCode: 404, code: "NOT_FOUND", message: "Not found")
private let locked = HTTPError(statusCode: 423, code: "APP_LOCKED", message: "Locked")

@Suite("GroupStream")
struct GroupStreamTests {
    private func stream(
        _ server: FakeServer, unlock: @escaping @Sendable () async -> Bool = { false },
        idleLimit: Duration = .seconds(45), sleepsForever: Bool = false
    ) -> GroupStream {
        GroupStream(
            connect: { server.connect() }, unlock: unlock,
            sleep: { duration in
                server.sleeps.withLock { $0.append(duration) }
                if sleepsForever { try await Task.sleep(for: .seconds(3600)) }
            }, idleLimit: idleLimit)
    }

    /// Reads updates until `stop` says so (or the stream ends), then lets go of it.
    private func collect(
        _ stream: GroupStream, until stop: @escaping ([GroupStreamUpdate]) -> Bool
    ) async -> [GroupStreamUpdate] {
        var seen: [GroupStreamUpdate] = []
        for await update in await stream.updates() {
            seen.append(update)
            if stop(seen) { break }
        }
        return seen
    }

    private func disconnects(_ updates: [GroupStreamUpdate]) -> Int { waits(updates).count }

    /// The waits announced, in order — each is the one then slept.
    private func waits(_ updates: [GroupStreamUpdate]) -> [Duration] {
        updates.compactMap { if case .disconnected(let retryIn) = $0 { retryIn } else { nil } }
    }

    @Test("each failure waits twice as long, up to thirty seconds")
    func backoffDoublesToThirty() async {
        let server = FakeServer([.fail(nil)])
        let updates = await collect(stream(server)) { disconnects($0) == 7 }
        #expect(waits(updates) == [1, 2, 4, 8, 16, 30, 30].map { Duration.seconds($0) })
        #expect(Array(server.slept.prefix(6)) == [1, 2, 4, 8, 16, 30].map { Duration.seconds($0) })
    }

    @Test("a connection that got a byte starts the wait over")
    func firstByteResetsBackoff() async {
        let server = FakeServer([.fail(nil), .fail(nil), .items([.heartbeat]), .fail(nil)])
        let updates = await collect(stream(server)) { disconnects($0) == 4 }
        #expect(waits(updates) == [1, 2, 1, 2].map { Duration.seconds($0) })
    }

    @Test("every connect says so, and events pass through")
    func connectedAndEvents() async {
        let server = FakeServer([.items([.event(.pmStarted(conversationId: "c1"))]), .fail(nil)])
        let updates = await collect(stream(server)) { disconnects($0) == 1 }
        #expect(updates.first == .connected)
        #expect(updates.dropFirst().first == .event(.pmStarted(conversationId: "c1")))
    }

    @Test("a connection silent past the idle limit is dropped and made again")
    func idleLimitDropsAndReconnects() async {
        let server = FakeServer([.silent])
        let updates = await collect(stream(server, idleLimit: .milliseconds(50))) { u in
            u.filter { $0 == .connected }.count == 2
        }
        #expect(server.connectCount >= 2)
        #expect(disconnects(updates) >= 1)
    }

    @Test("a group that is gone ends the stream")
    func notFoundIsGone() async {
        let server = FakeServer([.fail(notFound)])
        let updates = await collect(stream(server)) { _ in false }
        #expect(updates == [.gone])
        #expect(server.connectCount == 1)
    }

    @Test("a locked computer is unlocked once, then connected")
    func lockedConnectUnlocksOnce() async {
        let unlocks = Mutex(0)
        let server = FakeServer([.fail(locked), .items([])])
        let updates = await collect(
            stream(server, unlock: { unlocks.withLock { $0 += 1 }; return true })
        ) { $0.contains(.connected) }
        #expect(updates.first == .connected)
        #expect(unlocks.withLock { $0 } == 1)
        #expect(server.slept.isEmpty)

        let refused = FakeServer([.fail(locked)])
        let ended = await collect(stream(refused, unlock: { false })) { _ in false }
        #expect(ended == [.locked])
        #expect(refused.connectCount == 1)
    }

    @Test("coming back to the foreground connects at once")
    func foregroundReconnectsImmediately() async throws {
        let server = FakeServer([.fail(nil), .items([])])
        let stream = stream(server, sleepsForever: true)
        let reader = Task { await collect(stream) { u in u.contains(.connected) } }
        while server.slept.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        await stream.reconnectNow()
        let updates = await reader.value
        #expect(updates.contains(.connected))
        #expect(server.connectCount == 2)
    }
}
