import ChatFeature
import Foundation
import NetworkingKit

/// The offline chat cache lives and dies with the computer it was read from (ISSUE-242): unpairing, forgetting or
/// a revocation removes the computer, and with it its folder; switching to another computer removes nothing.
enum OfflineCacheLifecycle {
    /// `root` is the cache's folder (`OfflineChatStore.standardRoot` in the app).
    static func install(
        on connection: ServerConnection, root: URL = OfflineChatStore.standardRoot,
        status: ConnectionStatus = .shared
    ) {
        // Whoever is paired now keeps a folder; read at the event, when the removal is already in memory.
        connection.onComputerRemoved { [weak connection] in
            guard let connection else { return }
            OfflineChatStore.prune(root: root, keeping: Set(connection.pairedComputers.map(\.fingerprint)))
        }
        // The next computer starts clean: it may well be reachable when the last was not.
        connection.onComputerChange { Task { @MainActor in status.markOnline() } }
    }
}
