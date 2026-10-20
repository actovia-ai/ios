import Foundation

/// Every computer this device is paired with, and which one it talks to now. A person can run Actovia on more than
/// one Mac (a Mac mini at home with the release, a laptop with a development build) and switch between them in
/// Settings; each pairing is its own token and certificate pin, kept in the one Keychain item behind Face ID.
/// A computer is known by its certificate fingerprint: pairing the same computer again replaces its entry.
public struct PairedComputers: Codable, Equatable, Sendable {
    public var servers: [PairedServer]
    /// The computer requests go to; the first one when it names none that is here.
    public var activeFingerprint: String?

    public init(servers: [PairedServer] = [], activeFingerprint: String? = nil) {
        self.servers = servers
        self.activeFingerprint = activeFingerprint
    }

    public var isEmpty: Bool { servers.isEmpty }

    public var active: PairedServer? {
        servers.first { $0.fingerprint == activeFingerprint } ?? servers.first
    }

    /// Adds a pairing (or replaces the same computer's) and makes it the current one.
    public mutating func upsert(_ server: PairedServer) {
        if let index = servers.firstIndex(where: { $0.fingerprint == server.fingerprint }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        activeFingerprint = server.fingerprint
    }

    /// Replaces a stored entry in place (a new `lastGoodHost`), without changing which one is current.
    public mutating func update(_ server: PairedServer) {
        guard let index = servers.firstIndex(where: { $0.fingerprint == server.fingerprint }) else { return }
        servers[index] = server
    }

    /// Makes `fingerprint` the current computer; false when it is not paired.
    @discardableResult
    public mutating func select(_ fingerprint: String) -> Bool {
        guard servers.contains(where: { $0.fingerprint == fingerprint }) else { return false }
        activeFingerprint = fingerprint
        return true
    }

    /// Forgets one computer; when it was the current one, the next in the list takes its place.
    public mutating func remove(_ fingerprint: String) {
        let wasActive = active?.fingerprint == fingerprint
        servers.removeAll { $0.fingerprint == fingerprint }
        if wasActive || !servers.contains(where: { $0.fingerprint == activeFingerprint }) {
            activeFingerprint = servers.first?.fingerprint
        }
    }

    /// The Keychain item's contents: this list, or — written before a device could pair with more than one
    /// computer — a single `PairedServer`, which becomes a list of one.
    public static func decode(_ data: Data) throws -> PairedComputers {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode(PairedComputers.self, from: data) { return list }
        let single = try decoder.decode(PairedServer.self, from: data)
        return PairedComputers(servers: [single], activeFingerprint: single.fingerprint)
    }
}

/// One paired computer as Settings lists it — no token.
public struct PairedComputer: Identifiable, Equatable, Sendable {
    public var id: String { fingerprint }
    public let fingerprint: String
    public let name: String
    /// The address tried first (the one that answered last).
    public let host: String?
    public let isActive: Bool

    public init(fingerprint: String, name: String, host: String?, isActive: Bool) {
        self.fingerprint = fingerprint
        self.name = name
        self.host = host
        self.isActive = isActive
    }
}
