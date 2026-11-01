import Foundation
import NetworkingKit
import Testing

@testable import Actovia

private struct EmptyCredentials: CredentialStoring {
    var exists: Bool { false }
    func load(reason: String) async throws -> PairedComputers? { nil }
    func save(_ computers: PairedComputers) throws {}
    func clear() throws {}
}

@MainActor
@Suite("Scene services")
struct WindowServicesTests {
    @Test("each window has independent live connection, streams and offline status")
    func independent() {
        let first = WindowServices(store: EmptyCredentials())
        let second = WindowServices(store: EmptyCredentials())
        #expect(first.connection !== second.connection)
        #expect(first.streamManager !== second.streamManager)
        #expect(first.serverConfig !== second.serverConfig)
        #expect(first.apiClient.status !== second.apiClient.status)
        first.apiClient.status?.markOffline()
        #expect(second.apiClient.status?.isOffline == false)
    }
}
