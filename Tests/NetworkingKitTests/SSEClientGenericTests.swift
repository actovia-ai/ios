import Foundation
import Models
import Testing

@testable import NetworkingKit

/// Its own protocol class: `handler` is process-global, and other suites set theirs in parallel.
final class SSEMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SSEMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private struct Probe: Decodable, Sendable, Equatable {
    let type: String
}

@Suite("SSEClient: any event type", .serialized)
struct SSEClientGenericTests {
    private let request = URLRequest(url: URL(string: "https://computer.test/api/v1/philharmonic/conversations/c/sse")!)

    @Test("the answer opens the stream; a ping is a heartbeat and a data line an event, in order")
    func heartbeatThenEvent() async throws {
        SSEMockURLProtocol.body = Data(": ping\n\ndata: {\"type\":\"pm_started\"}\n\n".utf8)
        let client = SSEClient(session: SSEMockURLProtocol.makeSession())
        var items: [String] = []
        for try await item in client.events(Probe.self, for: request) {
            switch item {
            case .opened: items.append("opened")
            case .heartbeat: items.append("heartbeat")
            case .event(let probe): items.append(probe.type)
            }
        }
        #expect(items == ["opened", "heartbeat", "pm_started"])
    }

    @Test("the chat stream drops the heartbeat")
    func chatDropsHeartbeat() async throws {
        SSEMockURLProtocol.body = Data(": ping\n\ndata: {\"type\":\"title\",\"title\":\"t\"}\n\n".utf8)
        let client = SSEClient(session: SSEMockURLProtocol.makeSession())
        var count = 0
        for try await event in client.events(for: request) {
            guard case .title(let title) = event else {
                Issue.record("expected .title")
                continue
            }
            #expect(title == "t")
            count += 1
        }
        #expect(count == 1)
    }
}
