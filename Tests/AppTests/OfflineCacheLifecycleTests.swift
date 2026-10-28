import ChatFeature
import Foundation
import Models
import NetworkingKit
import Testing

@testable import Actovia

@MainActor
@Suite("Offline cache lifecycle")
struct OfflineCacheLifecycleTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)

    private func server(_ fingerprint: String) -> PairedServer {
        PairedServer(
            hosts: ["10.0.0.2"], port: 63129, fingerprint: fingerprint, name: "Mac \(fingerprint)",
            deviceId: "dev-\(fingerprint)", token: "T-\(fingerprint)")
    }

    /// Two paired computers (A active), each with a cached list, wired to the lifecycle over a scratch root.
    private func makeConnection() async throws -> ServerConnection {
        let store = InMemoryCredentialStore(
            computers: PairedComputers(servers: [server("A"), server("B")], activeFingerprint: "A"))
        let connection = ServerConnection(store: store)
        try await connection.unlock(reason: "test")
        for fingerprint in ["A", "B"] {
            OfflineChatStore(root: root, fingerprint: fingerprint).saveList(
                chats: [ChatSummary(id: fingerprint, title: "Chat", createdAt: "2026-10-01T10:00:00Z")],
                favorites: [], at: Date())
        }
        OfflineCacheLifecycle.install(on: connection, root: root, status: ConnectionStatus())
        return connection
    }

    @Test("a revoked computer's cache is deleted and the others' stays")
    func revokeDeletesThatComputersCache() async throws {
        let connection = try await makeConnection()
        connection.revoked(fingerprint: "B")
        #expect(OfflineChatStore(root: root, fingerprint: "B").loadList() == nil)
        #expect(OfflineChatStore(root: root, fingerprint: "A").loadList()?.chats.map(\.id) == ["A"])
    }

    @Test("switching computers keeps both caches")
    func switchKeepsBoth() async throws {
        let connection = try await makeConnection()
        try connection.switchTo(fingerprint: "B")
        #expect(OfflineChatStore(root: root, fingerprint: "A").loadList() != nil)
        #expect(OfflineChatStore(root: root, fingerprint: "B").loadList() != nil)
    }

    @Test("unpairing the active computer deletes its cache and starts the next one online")
    func unpairClearsAndGoesOnline() async throws {
        let status = ConnectionStatus()
        status.markOffline()
        let store = InMemoryCredentialStore(computers: PairedComputers(servers: [server("A"), server("B")], activeFingerprint: "A"))
        let connection = ServerConnection(store: store)
        try await connection.unlock(reason: "test")
        OfflineChatStore(root: root, fingerprint: "A").saveList(chats: [], favorites: [], at: Date())
        OfflineCacheLifecycle.install(on: connection, root: root, status: status)
        connection.unpair()
        #expect(OfflineChatStore(root: root, fingerprint: "A").loadList() == nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!status.isOffline)
    }
}
