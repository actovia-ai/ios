import Testing

@testable import ChatFeature

@Suite("SearchHighlight")
struct SearchHighlightTests {
    /// The substrings carrying a highlight, in order.
    private func marked(_ text: String, query: String) -> [String] {
        let attributed = SearchHighlight.attributed(text, query: query)
        return attributed.runs.filter { $0.foregroundColor != nil }.map { String(attributed[$0.range].characters) }
    }

    @Test("marks every occurrence of each query word")
    func marksEveryWord() {
        #expect(marked("Kyoto trip, Kyoto food", query: "kyoto food") == ["Kyoto", "Kyoto", "food"])
    }

    @Test("ignores case and diacritics, keeping the text's own spelling")
    func ignoresCaseAndDiacritics() {
        #expect(marked("Un café CRÈME", query: "CAFE creme") == ["café", "CRÈME"])
    }

    @Test("marks CJK words")
    func marksCJK() {
        #expect(marked("去京都旅行", query: "京都") == ["京都"])
    }

    @Test("text without a match, or a blank query, carries no mark and the text is unchanged")
    func noMatch() {
        #expect(marked("hello", query: "zzz").isEmpty)
        #expect(marked("hello", query: "  ").isEmpty)
        #expect(String(SearchHighlight.attributed("hello", query: "zzz").characters) == "hello")
    }
}
