import Foundation
import Models
import Testing

@testable import NetworkingKit

@Suite("ConnectionStatus", .serialized)
@MainActor
struct ConnectionStatusTests {
    private func fetch(_ client: APIClient) async -> Error? {
        do {
            let _: [String] = try await client.get("/api/v1/history")
            return nil
        } catch { return error }
    }

    private func makeClient(status: ConnectionStatus) -> APIClient {
        let config = ServerConfigStore(userDefaults: UserDefaults(suiteName: #function)!)
        return APIClient(session: MockURLProtocol.makeSession(), serverConfig: config, status: status)
    }

    @Test("starts online")
    func startsOnline() {
        #expect(!ConnectionStatus().isOffline)
    }

    @Test("a request that no route answered marks offline")
    func transportFailureMarksOffline() async {
        MockURLProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        let status = ConnectionStatus()
        let client = makeClient(status: status)
        #expect(await fetch(client) is URLError)
        #expect(status.isOffline)
    }

    @Test("any response, even a 500, marks online again")
    func anyResponseMarksOnline() async {
        MockURLProtocol.handler = { _ in (500, Data("boom".utf8)) }
        let status = ConnectionStatus()
        status.markOffline()
        let client = makeClient(status: status)
        #expect(await fetch(client) is HTTPError)
        #expect(!status.isOffline)
    }

    @Test("a success marks online again")
    func successMarksOnline() async throws {
        MockURLProtocol.handler = { _ in (200, Data("[]".utf8)) }
        let status = ConnectionStatus()
        status.markOffline()
        let chats: [String] = try await makeClient(status: status).get("/api/v1/history")
        #expect(chats.isEmpty)
        #expect(!status.isOffline)
    }

    @Test("a cancelled request leaves the state alone")
    func cancellationLeavesStateAlone() async {
        let status = ConnectionStatus()
        MockURLProtocol.handler = { _ in throw URLError(.cancelled) }
        let client = makeClient(status: status)
        _ = await fetch(client)
        #expect(!status.isOffline)

        status.markOffline()
        _ = await fetch(client)
        #expect(status.isOffline)
    }
}
