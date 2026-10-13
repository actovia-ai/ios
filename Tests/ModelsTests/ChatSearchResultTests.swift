import Foundation
import Testing

@testable import Models

@Suite("ChatSearchResult")
struct ChatSearchResultTests {
    @Test("decodes the server's chat rows with their snippets")
    func decodesTheContract() throws {
        let json = #"""
            [{"chatId":"c1","title":"Trip to Kyoto","matchedAt":"2026-10-14T08:00:00.000Z",
              "snippets":[
                {"messageId":"m2","role":"assistant","text":"…the best time for Kyoto is autumn…","createdAt":"2026-10-14T08:00:00.000Z"},
                {"messageId":"m1","role":"user","text":"Plan Kyoto","createdAt":"2026-10-13T08:00:00.000Z"}]},
             {"chatId":"c2","title":"Kyoto notes","matchedAt":"2026-10-12T08:00:00.000Z","snippets":[]}]
            """#
        let results = try JSONDecoder().decode([ChatSearchResult].self, from: Data(json.utf8))
        #expect(results.map(\.id) == ["c1", "c2"])
        #expect(results[0].title == "Trip to Kyoto")
        #expect(results[0].matchedAt == "2026-10-14T08:00:00.000Z")
        #expect(
            results[0].snippets.first
                == ChatSearchSnippet(
                    messageId: "m2", role: "assistant", text: "…the best time for Kyoto is autumn…",
                    createdAt: "2026-10-14T08:00:00.000Z"))
        #expect(results[0].snippets.count == 2)
        #expect(results[1].snippets.isEmpty)
    }

    @Test("an empty response is an empty list")
    func decodesEmpty() throws {
        #expect(try JSONDecoder().decode([ChatSearchResult].self, from: Data("[]".utf8)).isEmpty)
    }

    @Test("a row without matchedAt is rejected")
    func matchedAtIsRequired() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ChatSearchResult.self, from: Data(#"{"chatId":"c1","title":"T","snippets":[]}"#.utf8))
        }
    }
}
