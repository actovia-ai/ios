import Foundation
import Security

/// Computers unpaired on this device that could not be told at the time (off, or out of reach): each is told again
/// — `DELETE /api/v1/pair` with the token kept for that alone — until one answers, so the device leaves that
/// computer's Devices list too. A Keychain item of its own, readable while the device is unlocked (no Face ID: a
/// retry must not prompt), on this device only, never backed up; an entry goes once its computer has been told.
public protocol PendingLeaveStoring: Sendable {
    func load() -> [PairedServer]
    func save(_ leaves: [PairedServer])
}

public final class KeychainPendingLeaves: PendingLeaveStoring {
    private static let service = "app.yancey.actovia.pairing"
    private static let account = "pending-leaves"

    public init() {}

    private static func query() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> [PairedServer] {
        var query = Self.query()
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data
        else { return [] }
        return (try? JSONDecoder().decode([PairedServer].self, from: data)) ?? []
    }

    public func save(_ leaves: [PairedServer]) {
        SecItemDelete(Self.query() as CFDictionary)
        guard !leaves.isEmpty, let data = try? JSONEncoder().encode(leaves) else { return }
        var query = Self.query()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }
}

/// For tests and previews.
public final class InMemoryPendingLeaves: PendingLeaveStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var leaves: [PairedServer]

    public init(_ leaves: [PairedServer] = []) { self.leaves = leaves }

    public func load() -> [PairedServer] { lock.withLock { leaves } }
    public func save(_ leaves: [PairedServer]) { lock.withLock { self.leaves = leaves } }
}
