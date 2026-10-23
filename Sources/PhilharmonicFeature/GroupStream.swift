import Foundation
import Models
import NetworkingKit
import Synchronization

public enum GroupStreamUpdate: Sendable, Equatable {
    /// The server took the stream — on the first connect and every reconnect. Events sent while away are not
    /// replayed, so whoever reads this reads the group again.
    case connected
    case event(PhilharmonicSseEvent)
    case disconnected(retryIn: Duration)
    /// The group is gone (404): the stream has ended.
    case gone
    /// The computer is locked and unlocking it failed: the stream has ended.
    case locked
}

/// One open group's event stream, made again whenever it drops: 1, 2, 4, 8, 16, then every 30 s, starting over once
/// a connection has brought a byte. The server pings every 15 s, so `idleLimit` of silence is a dead connection.
public actor GroupStream {
    public typealias Connect = @Sendable () async throws -> AsyncThrowingStream<SSEItem<PhilharmonicSseEvent>, Error>

    private static let backoff: [Duration] = [1, 2, 4, 8, 16, 30].map { .seconds($0) }

    private let connect: Connect
    private let unlock: @Sendable () async -> Bool
    private let sleep: @Sendable (Duration) async throws -> Void
    private let idleLimit: Duration

    private var reading: Task<ReadEnd, Never>?
    private var sleeping: Task<Void, Never>?
    private var reconnectRequested = false

    public init(
        connect: @escaping Connect, unlock: @escaping @Sendable () async -> Bool,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        idleLimit: Duration = .seconds(45)
    ) {
        self.connect = connect
        self.unlock = unlock
        self.sleep = sleep
        self.idleLimit = idleLimit
    }

    /// The stream's updates; it runs until the consumer stops reading, the group is gone or the computer stays locked.
    public func updates() -> AsyncStream<GroupStreamUpdate> {
        AsyncStream { continuation in
            let task = Task {
                await self.run(continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Back in the foreground: a connection that slept with the app may be dead, and what it missed is not replayed,
    /// so make it again now, without waiting out a backoff.
    public func reconnectNow() {
        reconnectRequested = true
        sleeping?.cancel()
        reading?.cancel()
    }

    private func run(_ continuation: AsyncStream<GroupStreamUpdate>.Continuation) async {
        var attempt = 0
        var triedUnlock = false
        while !Task.isCancelled {
            switch await readOnce(continuation) {
            case .gone:
                continuation.yield(.gone)
                return
            case .locked:
                if !triedUnlock {
                    triedUnlock = true
                    if await unlock() { continue }
                }
                continuation.yield(.locked)
                return
            case .dropped(let opened, let sawByte):
                if opened { triedUnlock = false }
                if sawByte { attempt = 0 }
            }
            if Task.isCancelled { return }
            if reconnectRequested {
                reconnectRequested = false
                continue
            }
            let delay = Self.backoff[min(attempt, Self.backoff.count - 1)]
            attempt += 1
            continuation.yield(.disconnected(retryIn: delay))
            await pause(delay)
            reconnectRequested = false
        }
    }

    private func pause(_ delay: Duration) async {
        let task = Task { [sleep] in _ = try? await sleep(delay) }
        sleeping = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        sleeping = nil
    }

    private func readOnce(_ continuation: AsyncStream<GroupStreamUpdate>.Continuation) async -> ReadEnd {
        let task = Task { [connect, idleLimit] in
            await Self.read(connect: connect, idleLimit: idleLimit, continuation: continuation)
        }
        reading = task
        let end = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        reading = nil
        return end
    }

    private enum ReadEnd {
        case dropped(opened: Bool, sawByte: Bool)
        case gone
        case locked
    }

    private struct Dropped: Error {}

    /// What one connection has seen, read by its idle watchdog.
    private final class Activity: Sendable {
        private struct State {
            var last = ContinuousClock.now
            var opened = false
            var sawByte = false
        }

        private let state = Mutex(State())

        func note(opened: Bool = false, byte: Bool = false) {
            state.withLock {
                $0.last = .now
                if opened { $0.opened = true }
                if byte { $0.sawByte = true }
            }
        }

        var silence: Duration { state.withLock { ContinuousClock.now - $0.last } }
        var opened: Bool { state.withLock { $0.opened } }
        var sawByte: Bool { state.withLock { $0.sawByte } }
    }

    private static func read(
        connect: Connect, idleLimit: Duration, continuation: AsyncStream<GroupStreamUpdate>.Continuation
    ) async -> ReadEnd {
        let activity = Activity()
        do {
            let stream = try await connect()
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for try await item in stream {
                        switch item {
                        case .opened:
                            activity.note(opened: true)
                            continuation.yield(.connected)
                        case .heartbeat:
                            activity.note(byte: true)
                        case .event(let event):
                            activity.note(byte: true)
                            continuation.yield(.event(event))
                        }
                    }
                    throw Dropped()
                }
                group.addTask {
                    while true {
                        let silence = activity.silence
                        if silence >= idleLimit { throw Dropped() }
                        try await Task.sleep(for: idleLimit - silence)
                    }
                }
                _ = try await group.next()
            }
            return .dropped(opened: activity.opened, sawByte: activity.sawByte)
        } catch let error as HTTPError where error.statusCode == 404 {
            return .gone
        } catch let error as HTTPError where error.code == "APP_LOCKED" || error.statusCode == 423 {
            return .locked
        } catch {
            return .dropped(opened: activity.opened, sawByte: activity.sawByte)
        }
    }
}
