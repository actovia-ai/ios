import Foundation
import NetworkingKit
import Observation
import SwiftUI

/// What the computer's `GET /api/v1/entity/:title` answers (the desktop's `EntitySummary`): Wikipedia's summary of
/// the article, or `extract == nil` when neither the asked language nor English has it.
struct EntitySummary: Decodable, Equatable, Sendable {
    struct Thumbnail: Decodable, Equatable, Sendable {
        let source: String
        let width: Int
        let height: Int
    }

    let title: String
    let extract: String?
    let description: String?
    let thumbnail: Thumbnail?
    /// The article's page, to read more; nil when nothing was found.
    let url: String?
    let lang: String
}

/// Reads summaries through the computer (the phone has no network of its own but its computer's), once each per
/// title and language for the chat screen's life. A failure is thrown and asked again next time.
@MainActor @Observable
final class EntityLoader {
    typealias Fetch = @MainActor @Sendable (_ title: String, _ lang: String) async throws -> EntitySummary

    private let fetch: Fetch
    private var cache: [String: EntitySummary] = [:]

    init(fetch: @escaping Fetch) { self.fetch = fetch }

    convenience init(apiClient: APIClient) {
        self.init { title, lang in
            // The title is one path component: `appendingPathComponent` percent-encodes it.
            try await apiClient.get("/api/v1/entity/\(title)", query: [URLQueryItem(name: "lang", value: lang)])
        }
    }

    func summary(for title: String, lang: String) async throws -> EntitySummary {
        let key = lang + "/" + title
        if let hit = cache[key] { return hit }
        let summary = try await fetch(title, lang)
        cache[key] = summary
        return summary
    }

    /// Wikipedia's language for the phone's locale: the language code when it is two or three ASCII letters
    /// (`zh-Hant_TW` → `zh`, `pt_BR` → `pt`), else English — the desktop's `wikipediaLang`. Pure, so off the actor.
    nonisolated static func wikipediaLang(for locale: Locale) -> String {
        guard let code = locale.language.languageCode?.identifier.lowercased(), (2...3).contains(code.count),
            code.allSatisfy({ $0.isASCII && $0.isLetter })
        else { return "en" }
        return code
    }
}

extension EnvironmentValues {
    /// The chat screen's reader of entity summaries; nil (a gallery) shows the sheet's "could not reach" state.
    @Entry var entityLoader: EntityLoader?
}
