import Foundation

/// The links a widget opens the app with. Anything else — another scheme, an unknown path, a prompt too long — is not
/// a link, and the app ignores it.
public enum DeepLink: Equatable, Sendable {
    /// A fresh chat, its composer pre-filled when there is a prompt (never sent by itself), or opened on the camera
    /// or already recording.
    case newChat(prompt: String?, opening: Opening? = nil)
    case chat(id: String)
    /// Health, its ask box pre-filled when there is a question.
    case health(ask: String?)

    /// What a new chat opens on, from a widget's round buttons.
    public enum Opening: String, Sendable {
        case camera, voice
    }

    public static let scheme = "exodus"
    public static let maxPrompt = 500

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        switch self {
        case .newChat(let prompt, let opening):
            parts.host = "chat"
            parts.path = "/new"
            let items = [
                prompt.map { URLQueryItem(name: "prompt", value: $0) },
                opening.map { URLQueryItem(name: "open", value: $0.rawValue) },
            ].compactMap { $0 }
            parts.queryItems = items.isEmpty ? nil : items
        case .chat(let id):
            parts.host = "chat"
            parts.path = "/" + id
        case .health(let ask):
            parts.host = "health"
            parts.queryItems = ask.map { [URLQueryItem(name: "ask", value: $0)] }
        }
        // `URLQueryItem` escapes `&`, `=`, `%` and `#` in a value but leaves `+`, which form decoders read as a
        // space; only `+` is escaped here, so the value reads back whole.
        parts.percentEncodedQuery = parts.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        return parts.url!
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let path = parts.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        func query(_ name: String) -> String?? {
            let value = parts.queryItems?.first { $0.name == name }?.value
            guard let value, !value.isEmpty else { return .some(nil) }
            return value.count > Self.maxPrompt ? nil : .some(value)
        }
        switch (parts.host, path) {
        case ("chat", ["new"]):
            guard let prompt = query("prompt") else { return nil }
            // An opening the app does not know is not a link; an empty one is none.
            let open = parts.queryItems?.first { $0.name == "open" }?.value ?? ""
            let opening: Opening?
            if open.isEmpty {
                opening = nil
            } else if let known = Opening(rawValue: open) {
                opening = known
            } else {
                return nil
            }
            self = .newChat(prompt: prompt, opening: opening)
        case ("chat", let path) where path.count == 1 && Self.isAcceptableChatId(path[0]):
            self = .chat(id: path[0])
        case ("health", []):
            guard let ask = query("ask") else { return nil }
            self = .health(ask: ask)
        default:
            return nil
        }
    }

    /// The id goes into `/api/v1/chat/<id>/…`: only the characters of a UUID-like id, never `/` or `..`. The same
    /// rule as `DeepResearchStore.isAcceptableId` in ChatFeature, which this module cannot reach.
    static func isAcceptableChatId(_ id: String) -> Bool {
        (1...64).contains(id.count)
            && id.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" || $0 == "_" }
    }
}
