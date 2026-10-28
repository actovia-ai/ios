import Observation

/// Whether the computer answered the app's last request. `APIClient` feeds it: any HTTP response (whatever the
/// status) means the computer is there, a request that no address answered means it is not. Views read `isOffline`
/// to fall back to what is stored on the phone.
@MainActor @Observable
public final class ConnectionStatus {
    /// `nonisolated` so `APIClient`'s (nonisolated) init can default to it; the instance itself stays main-actor.
    public nonisolated static let shared = ConnectionStatus()

    public private(set) var isOffline = false

    public nonisolated init() {}

    public func markOffline() { if !isOffline { isOffline = true } }
    public func markOnline() { if isOffline { isOffline = false } }
}
