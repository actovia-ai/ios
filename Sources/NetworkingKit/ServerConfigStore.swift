import Foundation

/// `UserDefaults` itself is thread-safe but not marked `Sendable` by Foundation;
/// this type has no other mutable state, so `@unchecked` is a deliberate,
/// narrow override, not a blanket escape hatch.
public final class ServerConfigStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private static let key = "actovia.serverURL"
    private static let defaultBaseURL = "http://localhost:60223"

    /// The paired computer, when there is one. Set once at start-up.
    public var connection: ServerConnection?

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// The manually entered address — what the Simulator uses to reach the
    /// computer's plain loopback listener. A device cannot: it has to pair.
    public var manualBaseURLString: String {
        get { userDefaults.string(forKey: Self.key) ?? Self.defaultBaseURL }
        set { userDefaults.set(newValue, forKey: Self.key) }
    }

    /// Where requests go, taken in one piece: the current paired computer's addresses, token and pinned session;
    /// the manual address (and the caller's own session) while unpaired. Paired but locked behind Face ID, nothing:
    /// a paired device never falls back to the plain address, where a request would leave in cleartext.
    public var route: ServerRoute {
        if let route = connection?.route { return route }
        if connection?.isPaired == true {
            return ServerRoute(bases: [], authorization: nil, session: nil, fingerprint: nil)
        }
        return ServerRoute(bases: [manualBaseURLString], authorization: nil, session: nil, fingerprint: nil)
    }

    /// The first address of `route` ("" when there is none, which no request can be built from).
    public var baseURLString: String {
        get { route.bases.first ?? "" }
        set { manualBaseURLString = newValue }
    }

    /// Where requests may go, best first — see `ServerConnection.baseURLCandidates`.
    public var baseURLCandidates: [String] { route.bases }

    /// `Authorization` for the paired computer; nil for the manual address.
    public var authorization: String? { route.authorization }
}
