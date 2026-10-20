import Foundation
import Models

/// Where one request goes, taken in one piece (`ServerConnection.route`): the paired computer's addresses, its
/// token, and the session that trusts its certificate and nothing else. Reading the three at different moments
/// would let a switch between computers put one computer's token on the other's address or connection.
public struct ServerRoute: Sendable {
    /// Best first (`PairedServer.orderedHosts`).
    public let bases: [String]
    public let authorization: String?
    /// The computer's own pinned session; nil for the plain manual address, where the caller's session serves.
    public let session: URLSession?
    /// The computer this route is to: a 401 forgets that one, an address that answered is noted on that one —
    /// not whichever is current by the time the answer comes.
    public let fingerprint: String?

    public init(bases: [String], authorization: String?, session: URLSession?, fingerprint: String?) {
        self.bases = bases
        self.authorization = authorization
        self.session = session
        self.fingerprint = fingerprint
    }
}

/// The paired computers, once Face ID has released them, and the one requests go to now (`PairedComputers`;
/// Settings switches between them). Held in memory only:
/// `lock()` — called after five minutes in the background — forgets it, and the
/// next use goes back through the Keychain, and so through Face ID.
///
/// Every computer has a session of its own (`route`), whose `PinnedSessionDelegate` trusts that computer's
/// certificate and no other, so its pool of TLS connections is its own: no token is ever sent down a connection
/// that was checked against another computer, whatever addresses the two share and however a switch interleaves
/// with requests in flight.
///
/// While unpaired it contributes nothing, and the app talks to the plain address in `ServerConfigStore` — the
/// Simulator reaching the computer's loopback listener.
public final class ServerConnection: @unchecked Sendable {
    /// How long the app may sit in the background before it locks.
    public static let backgroundGrace: TimeInterval = 300

    private let store: CredentialStoring
    private let state = NSLock()
    private var computers: PairedComputers?
    /// The computer requests go to: the current one of `computers`. Read under `state`.
    private var server: PairedServer? { computers?.active }
    /// The pin to trust while pairing, before there is a stored server.
    private var pendingPin: String?
    private var computerChangeHandlers: [@Sendable () -> Void] = []
    /// One pinned session per computer, by fingerprint; made on first use, invalidated when it is unpaired.
    private var sessions: [String: URLSession] = [:]
    private let makeSession: @Sendable (String) -> URLSession

    /// `sessionFactory` is for tests: by default each computer's session trusts exactly its own certificate.
    public init(store: CredentialStoring, sessionFactory: (@Sendable (String) -> URLSession)? = nil) {
        self.store = store
        makeSession =
            sessionFactory ?? { fingerprint in
                URLSession(
                    configuration: ServerConnection.noStoreConfiguration(),
                    delegate: PinnedSessionDelegate(pin: { fingerprint }), delegateQueue: nil)
            }
    }

    /// The session for pairing and for the plain manual address: it trusts only the certificate a pairing in
    /// progress named (`pendingPin`), so no paired computer's token is ever sent through it. Plain-http requests —
    /// the Simulator on the manual address — pass through it untouched.
    public private(set) lazy var session: URLSession = URLSession(
        configuration: Self.noStoreConfiguration(),
        delegate: PinnedSessionDelegate(pin: { [weak self] in self?.state.withLock { self?.pendingPin } }),
        delegateQueue: nil)

    /// Responses carry provider keys and MCP tokens: nothing of them may land in a cache on disk.
    static func noStoreConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    /// A credential exists (it may still be locked behind Face ID).
    public var isPaired: Bool { store.exists }
    public var isUnlocked: Bool { state.withLock { computers != nil } }
    public var serverName: String? { state.withLock { server?.name } }
    public var currentHost: String? { state.withLock { server?.orderedHosts.first } }

    /// The certificate requests are pinned to right now: a pairing's, else the current computer's.
    public var pin: String? { state.withLock { pendingPin ?? server?.fingerprint } }
    public var authorization: String? { route?.authorization }
    public var baseURLString: String? { route?.bases.first }

    /// Every address the computer can be reached at, best first: the one that
    /// answered last time, then the rest in QR-code order — the LAN address on
    /// the home Wi-Fi, the tailnet address from anywhere else. Callers try them
    /// in turn (see `APIClient`) and report back through `noteReachable`.
    public var baseURLCandidates: [String] { route?.bases ?? [] }

    /// The current computer's addresses, token and session, read together; nil while unpaired or locked.
    public var route: ServerRoute? {
        state.withLock {
            guard let server else { return nil }
            return ServerRoute(
                bases: server.orderedHosts.map { server.baseURLString(host: $0) },
                authorization: "Bearer \(server.token)",
                session: sessionLocked(for: server.fingerprint),
                fingerprint: server.fingerprint)
        }
    }

    /// Under `state`.
    private func sessionLocked(for fingerprint: String) -> URLSession {
        if let existing = sessions[fingerprint] { return existing }
        let made = makeSession(fingerprint)
        sessions[fingerprint] = made
        return made
    }

    /// Reads the credential — this is the Face ID prompt.
    public func unlock(reason: String) async throws {
        let loaded = try await store.load(reason: reason)
        state.withLock { computers = loaded }
    }

    public func lock() {
        state.withLock { computers = nil }
    }

    /// Every paired computer, the current one marked — known once Face ID has released them.
    public var pairedComputers: [PairedComputer] {
        state.withLock {
            guard let computers else { return [] }
            let active = computers.active?.fingerprint
            return computers.servers.map {
                PairedComputer(
                    fingerprint: $0.fingerprint, name: $0.name, host: $0.orderedHosts.first,
                    isActive: $0.fingerprint == active)
            }
        }
    }

    /// Talk to another paired computer from now on. What was kept in memory from the one before goes with it
    /// (`onComputerChange`), and the app's screens start again on the new one. A request already on its way to the
    /// one before finishes there, with that computer's own token and session.
    public func switchTo(fingerprint: String) throws {
        let updated: PairedComputers? = state.withLock {
            guard var current = computers, current.active?.fingerprint != fingerprint,
                current.select(fingerprint)
            else { return nil }
            return current
        }
        guard let updated else { return }
        try store.save(updated)
        state.withLock { computers = updated }
        computerChanged()
    }

    /// Lifts the computer's own lock — a separate thing from this device's token being locked
    /// behind Face ID (see `UnlockGate`); this is the computer itself refusing all `/api/*`
    /// access (actovia's `src/main/lib/server/middlewares/lock-gate.ts`). A paired device's
    /// token is already proof enough, so this reads the token from memory (or, if it went
    /// stale, with the same Face ID prompt `unlock(reason:)` always uses) and sends it — no PIN,
    /// no second biometric prompt of its own. `APIClient` and `ChatStreamManager` both call this
    /// on a 423 before retrying the request that hit it, passing the route that request took, so
    /// the unlock goes to that computer; returns whether it actually unlocked.
    @discardableResult
    public func unlockComputer(route given: ServerRoute? = nil) async -> Bool {
        guard isPaired else { return false }
        if given == nil, !isUnlocked {
            try? await unlock(
                reason: String(
                    localized: "ios:app.lock.biometricReason", defaultValue: "Unlock the connection to your computer",
                    comment: "The reason shown in the Face ID / passcode prompt."))
        }
        guard let route = given ?? route, let session = route.session, let base = route.bases.first,
            let url = URL(string: base)?.appendingPathComponent("/api/v1/lock/unlock")
        else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let authorization = route.authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        guard let (_, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse
        else { return false }
        return (200..<300).contains(http.statusCode)
    }

    /// Unpairing from this device: forgotten here at once, then the computer is told (`DELETE /api/v1/pair`, with
    /// this device's own token, taken before it is forgotten) so it leaves the computer's Devices list too. The
    /// computer may be off or out of reach — each address gets a few seconds, one after another — so the screen does
    /// not wait for it; the computer's Devices page can still remove a device it was never told about.
    /// Returns the telling, for a test to wait on; `nil` when there is no token to tell with.
    @discardableResult
    public func leave(session: URLSession? = nil) -> Task<Void, Never>? {
        guard let fingerprint = state.withLock({ server?.fingerprint }) else {
            unpair()
            return nil
        }
        return forget(fingerprint: fingerprint, session: session)
    }

    /// Unpairs one computer, the current one or another: forgotten here at once, then told, as `leave` describes —
    /// over that computer's own pinned session (a test may pass its own), which is invalidated once told. When the
    /// current one goes, the next paired computer takes its place.
    @discardableResult
    public func forget(fingerprint: String, session: URLSession? = nil) -> Task<Void, Never>? {
        let (gone, own): (PairedServer?, URLSession?) = state.withLock {
            let gone = computers?.servers.first { $0.fingerprint == fingerprint }
            return (gone, gone.map { sessionLocked(for: $0.fingerprint) })
        }
        remove(fingerprint: fingerprint, keepSession: true)
        guard let gone, let own else { return nil }
        let urlSession = session ?? own
        let token = "Bearer \(gone.token)"
        let candidates = gone.orderedHosts.map { gone.baseURLString(host: $0) }
        return Task.detached {
            defer { own.invalidateAndCancel() }
            for base in candidates {
                guard let url = URL(string: base)?.appendingPathComponent("/api/v1/pair") else { continue }
                var request = URLRequest(url: url, timeoutInterval: 5)
                request.httpMethod = "DELETE"
                request.setValue(token, forHTTPHeaderField: "Authorization")
                if let (_, response) = try? await urlSession.data(for: request), response is HTTPURLResponse {
                    break  // It answered: told, or already gone (a 401) — either way done.
                }
            }
        }
    }

    /// Forget the current computer: unpaired here. Another paired computer, if there is one, becomes the current one.
    public func unpair() {
        guard let fingerprint = state.withLock({ server?.fingerprint }) else {
            let all: [URLSession] = state.withLock {
                defer { sessions = [:] }
                return Array(sessions.values)
            }
            all.forEach { $0.invalidateAndCancel() }
            try? store.clear()
            lock()
            computerChanged()
            return
        }
        remove(fingerprint: fingerprint, keepSession: false)
    }

    /// The computer a request went to refused its token (a 401): this device was revoked there. That computer is
    /// forgotten — the one the request was to (`ServerRoute.fingerprint`), which need not be the current one any
    /// more.
    public func revoked(fingerprint: String) {
        remove(fingerprint: fingerprint, keepSession: false)
    }

    /// Takes a computer off the list; its session goes too unless `forget` still has to tell it.
    private func remove(fingerprint: String, keepSession: Bool) {
        let (remaining, wasActive, session): (PairedComputers?, Bool, URLSession?) = state.withLock {
            guard var current = computers, current.servers.contains(where: { $0.fingerprint == fingerprint })
            else { return (computers, false, nil) }
            let wasActive = current.active?.fingerprint == fingerprint
            current.remove(fingerprint)
            computers = current.isEmpty ? nil : current
            return (computers, wasActive, keepSession ? nil : sessions.removeValue(forKey: fingerprint))
        }
        if keepSession { state.withLock { _ = sessions.removeValue(forKey: fingerprint) } }
        session?.invalidateAndCancel()
        if let remaining { try? store.save(remaining) } else { try? store.clear() }
        if wasActive { computerChanged() }
    }

    /// Runs `handler` whenever the paired computer goes (unpaired, revoked) or another is paired, so what was kept in
    /// memory from the old one (its screenshots, its images) goes with it.
    public func onComputerChange(_ handler: @escaping @Sendable () -> Void) {
        state.withLock { computerChangeHandlers.append(handler) }
    }

    private func computerChanged() {
        for handler in state.withLock({ computerChangeHandlers }) { handler() }
    }

    /// Remember which address worked, so it is tried first next time — on the computer that answered (`fingerprint`,
    /// from the request's route), or the current one.
    public func noteReachable(host: String, fingerprint: String? = nil) {
        let updated: PairedComputers? = state.withLock {
            guard var all = computers,
                var current = fingerprint.flatMap({ fp in all.servers.first { $0.fingerprint == fp } }) ?? server,
                current.lastGoodHost != host, current.hosts.contains(host)
            else { return nil }
            current.lastGoodHost = host
            all.update(current)
            computers = all
            return all
        }
        if let updated { try? store.save(updated) }
    }

    private struct PairRequest: Encodable {
        let code: String
        let deviceName: String
    }

    private struct PairResponse: Decodable {
        let deviceId: String
        let token: String
    }

    /// Trades the QR code's one-time code for a token, trying each address the
    /// code listed until one answers. Uses the pinned `session` unless a test
    /// passes its own — the pin it trusts meanwhile is the one the QR code named.
    public func pair(_ link: PairingLink, deviceName: String, session: URLSession? = nil) async throws {
        let session = session ?? self.session
        state.withLock { pendingPin = link.fingerprint }
        defer { state.withLock { pendingPin = nil } }

        var lastError: Error = URLError(.cannotConnectToHost)
        for host in link.hosts {
            let authority = host.contains(":") ? "[\(host)]" : host
            guard let url = URL(string: "https://\(authority):\(link.port)/api/v1/pair") else { continue }
            var request = URLRequest(url: url, timeoutInterval: 6)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                PairRequest(code: link.code, deviceName: deviceName))

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                lastError = error  // unreachable by this address — try the next
                continue
            }
            guard let http = response as? HTTPURLResponse else { continue }
            guard http.statusCode == 200 else {
                // The computer answered: the code is wrong, spent or expired.
                // Another address will say the same.
                throw HTTPError(
                    statusCode: http.statusCode, code: "PAIRING_FAILED",
                    message: String(
                        localized: "ios:networking.pairing.codeRejected",
                        defaultValue: "This pairing code is no longer valid. Show a new one on your computer.",
                        comment: "Error: the computer refused the pairing code (used, expired or wrong)."))
            }
            let reply = try JSONDecoder().decode(PairResponse.self, from: data)
            let paired = PairedServer(
                hosts: link.hosts, port: link.port, fingerprint: link.fingerprint, name: link.name,
                deviceId: reply.deviceId, token: reply.token, lastGoodHost: host)
            // Another computer is added beside those already paired, and becomes the current one. Those are in
            // memory once Face ID has released them; pairing from the welcome screen has none to keep. A computer
            // paired again (same certificate) gets a fresh session: nothing pooled under the old token carries on.
            var all = state.withLock { computers } ?? PairedComputers()
            all.upsert(paired)
            try store.save(all)
            let stale: URLSession? = state.withLock {
                computers = all
                return sessions.removeValue(forKey: paired.fingerprint)
            }
            stale?.invalidateAndCancel()
            computerChanged()
            return
        }
        throw lastError
    }
}
