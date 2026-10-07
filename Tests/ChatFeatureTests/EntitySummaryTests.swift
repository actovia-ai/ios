import Foundation
import Testing

@testable import ChatFeature

@Suite("EntitySummary and EntityLoader: Wikipedia's summary through the computer")
struct EntitySummaryTests {
    @Test("decodes what the route answers, nulls included")
    func decodes() throws {
        let found = #"{"title":"Marie Curie","extract":"Physicist.","description":"Polish-French physicist","thumbnail":{"source":"https://upload.wikimedia.org/x.jpg","width":330,"height":448},"url":"https://en.wikipedia.org/wiki/Marie_Curie","lang":"en"}"#
        let summary = try JSONDecoder().decode(EntitySummary.self, from: Data(found.utf8))
        #expect(summary.title == "Marie Curie")
        #expect(summary.thumbnail?.width == 330)
        #expect(summary.url == "https://en.wikipedia.org/wiki/Marie_Curie")
        let nothing = #"{"title":"Nobody Here","extract":null,"description":null,"thumbnail":null,"url":null,"lang":"en"}"#
        let none = try JSONDecoder().decode(EntitySummary.self, from: Data(nothing.utf8))
        #expect(none.extract == nil)
        #expect(none.thumbnail == nil)
    }

    @Test("Wikipedia's language for the phone's locale", arguments: [
        ("en_US", "en"), ("zh-Hant_TW", "zh"), ("zh-Hant_HK", "zh"), ("pt_BR", "pt"), ("ja_JP", "ja"), ("ko_KR", "ko"),
        ("de", "de"), ("yue", "yue"), ("", "en"),
    ])
    func lang(_ identifier: String, _ expected: String) {
        #expect(EntityLoader.wikipediaLang(for: Locale(identifier: identifier)) == expected, "\(identifier)")
    }

    /// What the fake computer was asked; a class on the main actor, since the loader's fetch is a `@Sendable` closure.
    @MainActor
    private final class Recorder {
        var asked: [(String, String)] = []
        var calls = 0
    }

    @Test("asks the computer once per title and language, and remembers the answer")
    @MainActor
    func caches() async throws {
        let recorder = Recorder()
        let summary = EntitySummary(title: "Kyoto", extract: "A city.", description: nil, thumbnail: nil, url: nil, lang: "en")
        let loader = EntityLoader { title, lang in
            recorder.asked.append((title, lang))
            return summary
        }
        #expect(try await loader.summary(for: "Kyoto", lang: "en") == summary)
        #expect(try await loader.summary(for: "Kyoto", lang: "en") == summary)
        _ = try await loader.summary(for: "Kyoto", lang: "ja")
        #expect(recorder.asked.map(\.0) == ["Kyoto", "Kyoto"])
        #expect(recorder.asked.map(\.1) == ["en", "ja"])
    }

    @Test("a failure is thrown, not remembered")
    @MainActor
    func failure() async {
        let recorder = Recorder()
        let loader = EntityLoader { _, _ in
            recorder.calls += 1
            throw URLError(.notConnectedToInternet)
        }
        await #expect(throws: URLError.self) { try await loader.summary(for: "Kyoto", lang: "en") }
        await #expect(throws: URLError.self) { try await loader.summary(for: "Kyoto", lang: "en") }
        #expect(recorder.calls == 2)
    }

    @Test("Read more opens the article only over https")
    func readMore() {
        #expect(
            EntitySheet.readMoreURL("https://en.wikipedia.org/wiki/Kyoto")
                == URL(string: "https://en.wikipedia.org/wiki/Kyoto"))
        #expect(EntitySheet.readMoreURL("http://en.wikipedia.org/wiki/Kyoto") == nil)
        #expect(EntitySheet.readMoreURL("javascript:alert(1)") == nil)
        #expect(EntitySheet.readMoreURL(nil) == nil)
    }
}
