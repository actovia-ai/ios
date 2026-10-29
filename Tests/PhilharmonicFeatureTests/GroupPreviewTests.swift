import Testing

@testable import PhilharmonicFeature

@Suite("GroupPreview (ISSUE-286: the drawer's last-message line is plain text)")
struct GroupPreviewTests {
    @Test(
        "markdown comes off",
        arguments: [
            ("**Jordan** booked the table", "Jordan booked the table"),
            (#"\*\*Saihō-ji\*\* opens at 9"#, "Saihō-ji opens at 9"),
            ("_Draft two_ is up: see [the doc](https://example.com/d)", "Draft two is up: see the doc"),
            ("## Plan\n\n1. Book\n2. Pack `bags`", "Plan Book Pack bags"),
            ("> quoted *line*", "quoted line"),
        ])
    func strips(source: String, expected: String) {
        #expect(GroupPreview.text(source) == expected)
    }

    @Test("an empty message stays empty, so the row says it has none")
    func empty() {
        #expect(GroupPreview.text("") == "")
        #expect(GroupPreview.text("  \n ") == "")
    }

    @Test("snake_case and a single * are words, not markup")
    func keepsSingleMarkers() {
        #expect(GroupPreview.text("set max_tokens to 5 * 2") == "set max_tokens to 5 * 2")
    }
}
