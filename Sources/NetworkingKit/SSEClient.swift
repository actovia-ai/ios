import Foundation
import Models

public struct SSEClient: Sendable {
    /// For the plain manual address; a paired computer's request passes that computer's own session.
    let session: URLSession
    let reporter: LogReporter?

    public init(session: URLSession = .shared, reporter: LogReporter? = nil) {
        self.session = session
        self.reporter = reporter
    }

    /// `session`: the paired computer's own (its `ServerRoute.session`); nil uses this client's.
    public func events(for request: URLRequest, session given: URLSession? = nil) -> AsyncThrowingStream<ChatSseEvent, Error> {
        let items = events(ChatSseEvent.self, for: request, session: given)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await item in items {
                        if case .event(let event) = item { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Any stream's events, and a `.heartbeat` for each `:` line the server sends to say it is still there.
    public func events<E: Decodable & Sendable>(
        _ type: E.Type, for request: URLRequest, session given: URLSession? = nil
    ) -> AsyncThrowingStream<SSEItem<E>, Error> {
        let session = given ?? self.session
        return AsyncThrowingStream { continuation in
            let reporter = self.reporter
            let path = request.url?.path ?? ""
            let task = Task {
                var issues = SSEFrameIssues()
                defer { issues.report(path: path, reporter: reporter) }
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        if let envelope = try? JSONDecoder().decode(ServerErrorEnvelope.self, from: body) {
                            throw HTTPError(statusCode: http.statusCode, code: envelope.error.code, message: envelope.error.message)
                        }
                        throw HTTPError(
                            statusCode: http.statusCode, code: "UNKNOWN_ERROR",
                            message: String(
                                localized: "ios:networking.error.httpStatus", defaultValue: "HTTP \(http.statusCode)",
                                comment:
                                    "Fallback error text for a server response without a message. %lld is the HTTP status code."
                            ))
                    }
                    continuation.yield(.opened)
                    for try await line in bytes.lines {
                        switch SSEFrameParsing.frame(E.self, fromLine: line) {
                        case .event(let event):
                            continuation.yield(.event(event))
                        case .comment:
                            continuation.yield(.heartbeat)
                        case .undecodable(let type, let reason, let bytes):
                            issues.note(type: type, reason: reason, bytes: bytes)
                        case .ignored:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// One item of a stream: the server's 2xx answer (first, once), an event, or the server's heartbeat.
public enum SSEItem<E: Sendable>: Sendable {
    /// The server took the request: what follows is the stream. A group stream sends no byte until something
    /// happens, so this is the only sign a reconnect worked.
    case opened
    case event(E)
    case heartbeat
}
