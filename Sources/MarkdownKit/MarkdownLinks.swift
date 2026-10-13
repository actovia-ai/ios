import SwiftUI

/// What a tap on a link in model-written text does. Only web and mail links leave the app, like the
/// desktop's `openExternalSafely`: `tel:`, `sms:`, `shortcuts:`, `file:` and other apps' schemes are
/// reachable by injected text, so they are dropped. An `entity:` link opens the host's panel for the article.
enum MarkdownLinkAction: Equatable {
    case citation(Int)
    case open(URL)
    /// `[Marie Curie](entity:Marie_Curie)`: the article's title, decoded.
    case entity(String)
    case discard
}

enum MarkdownLinkPolicy {
    static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    static func action(for url: URL) -> MarkdownLinkAction {
        if let number = MarkdownPreprocessor.citationNumber(from: url) { return .citation(number) }
        if let title = MarkdownEntityLink.title(from: url) { return .entity(title) }
        guard let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else { return .discard }
        return .open(url)
    }
}

/// `[Marie Curie](entity:Marie_Curie)` — a link that opens a short Wikipedia summary (spec 2026-10-07 §2.2). The
/// desktop's `entity-link.ts` rule, held to the same vectors: the scheme is `entity`, written in lowercase; the rest,
/// percent-escapes decoded, is 1–200 UTF-16 units of letters, digits and `_ ( ) . , ' - :` with at least one letter
/// or digit (so `.` and `..` are not titles). Anything else is text, never a link.
public enum MarkdownEntityLink {
    public static let scheme = "entity"
    public static let maxUnits = 200

    public static func title(from url: URL) -> String? {
        let string = url.absoluteString
        guard string.hasPrefix(scheme + ":") else { return nil }
        guard let title = String(string.dropFirst(scheme.count + 1)).removingPercentEncoding else { return nil }
        return isTitle(title) ? title : nil
    }

    public static func isTitle(_ title: String) -> Bool {
        guard (1...maxUnits).contains(title.utf16.count) else { return false }
        var hasWord = false
        for scalar in title.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                .decimalNumber, .letterNumber, .otherNumber:
                hasWord = true
            default:
                guard Self.punctuation.contains(scalar) else { return false }
            }
        }
        return hasWord
    }

    private static let punctuation = Set("_().,'-:".unicodeScalars)
}

/// Owns the one `OpenURLAction` a `MarkdownView` puts in its environment. The action is created once, so
/// its identity never changes while a message streams; the handlers it routes to are refreshed instead.
@MainActor
final class MarkdownLinkRouter {
    var onCitationTap: ((Int) -> Void)?
    var openURL: ((URL) -> Void)?
    /// An entity link's title, for the host's panel; nil handles the tap and does nothing.
    var onEntityTap: ((String) -> Void)?

    private(set) lazy var action = OpenURLAction { [weak self] url in
        MainActor.assumeIsolated { self?.handle(url) ?? .discarded }
    }

    func handle(_ url: URL) -> OpenURLAction.Result {
        switch MarkdownLinkPolicy.action(for: url) {
        case .citation(let number):
            onCitationTap?(number)
            return .handled
        case .open(let url):
            openURL?(url)
            return .handled
        case .entity(let title):
            onEntityTap?(title)
            return .handled
        case .discard:
            return .discarded
        }
    }
}
