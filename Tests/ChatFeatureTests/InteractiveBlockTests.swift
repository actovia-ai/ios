import Foundation
import Testing

@testable import ChatFeature

// The same vectors as the desktop's tests/unit/shared/types/interactive.test.ts — keep them in step.
private let askSource =
    #"{"title":"我想先确认一下你的具体情况","questions":[{"id":"where","text":"哪里最痒？","type":"single","options":["小腿","手臂","全身到处都痒"],"other":true},{"id":"when","text":"什么时候最痒？","type":"multi","options":["洗澡后","晚上","全天"]}],"note":"还有什么想补充的？","submit":"提交，帮我判断"}"#
private let confirmSource =
    #"{"title":"要我把这份行程写进日历吗？","details":"10 月 21–25 日，五天，17 个地点；日历「旅行」。","approve":"写进去","reject":"先不要","note":"有要改的地方可以写在这里"}"#

private func q(_ id: String, _ extra: [String: Any] = [:]) -> [String: Any] {
    ["id": id, "text": "Q \(id)", "type": "single", "options": ["x", "y"]].merging(extra) { $1 }
}
private func json(_ object: Any) -> String {
    String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self)
}
private func ask(_ extra: [String: Any] = [:]) -> String { json(["title": "T", "questions": [q("a")]].merging(extra) { $1 }) }
private func confirm(_ extra: [String: Any] = [:]) -> String { json(["title": "T"].merging(extra) { $1 }) }
private func repeated(_ s: String, _ n: Int) -> String { String(repeating: s, count: n) }

private let askCases: [(String, String, Bool)] = [
    ("the spec's example", askSource, true),
    ("eight questions", ask(["questions": (0..<8).map { q("q\($0)") }]), true),
    ("nine questions", ask(["questions": (0..<9).map { q("q\($0)") }]), false),
    ("no questions", ask(["questions": [Any]()]), false),
    ("an 80-character option", ask(["questions": [q("a", ["options": [repeated("x", 80), "y"]])]]), true),
    ("an 81-character option", ask(["questions": [q("a", ["options": [repeated("x", 81), "y"]])]]), false),
    ("40 emoji (80 UTF-16 units)", ask(["questions": [q("a", ["options": [repeated("😀", 40), "y"]])]]), true),
    ("41 emoji (82 UTF-16 units)", ask(["questions": [q("a", ["options": [repeated("😀", 41), "y"]])]]), false),
    ("one option", ask(["questions": [q("a", ["options": ["x"]])]]), false),
    ("nine options", ask(["questions": [q("a", ["options": (0..<9).map { String($0) }])]]), false),
    ("the same option twice", ask(["questions": [q("a", ["options": ["x", "x"]])]]), false),
    ("two questions with one id", ask(["questions": [q("a"), q("a")]]), false),
    ("an id with a capital", ask(["questions": [q("Where")]]), false),
    ("a 33-character id", ask(["questions": [q(repeated("a", 33))]]), false),
    ("a type that is neither single nor multi", ask(["questions": [q("a", ["type": "text"])]]), false),
    ("an empty title", ask(["title": ""]), false),
    ("a 201-character question", ask(["questions": [q("a", ["text": repeated("q", 201)])]]), false),
    ("a title on two lines", ask(["title": "A few\ndetails"]), false),
    ("a question on two lines", ask(["questions": [q("a", ["text": "Where?\nAnd when?"])]]), false),
    ("an option with a carriage return", ask(["questions": [q("a", ["options": ["x\ry", "z"]])]]), false),
    ("two questions with one text", ask(["questions": [q("a"), q("b", ["text": "Q a"])]]), false),
    ("two questions with different texts", ask(["questions": [q("a"), q("b")]]), true),
    ("a 121-character note", ask(["note": repeated("n", 121)]), false),
    ("a 41-character submit", ask(["submit": repeated("s", 41)]), false),
    ("nulls for what is optional", ask(["note": NSNull(), "submit": NSNull(), "questions": [q("a", ["other": NSNull()])]]), true),
    ("keys it does not know", ask(["colour": "red"]), true),
    ("not JSON", #"{"title":"#, false),
    ("an array", "[]", false),
]

private let confirmCases: [(String, String, Bool)] = [
    ("the spec's example", confirmSource, true),
    ("a title alone", confirm(), true),
    ("a title with a carriage return", confirm(["title": "Send\rit?"]), false),
    ("no title", json(["details": "d"]), false),
    ("a 201-character title", confirm(["title": repeated("t", 201)]), false),
    ("1000 characters of details", confirm(["details": repeated("d", 1000)]), true),
    ("1001 characters of details", confirm(["details": repeated("d", 1001)]), false),
    ("a 41-character approve", confirm(["approve": repeated("a", 41)]), false),
    ("a 41-character reject", confirm(["reject": repeated("r", 41)]), false),
    ("a 121-character note", confirm(["note": repeated("n", 121)]), false),
]

private let stepsSource =
    #"{"title":"Replacing the strings","steps":[{"text":"Loosen the old string from the tuning peg.","image":"https://imgs.search.brave.com/peg.jpg"},{"text":"Thread the new one through the bridge."},{"text":"Tune up slowly, stretching the string as you go.","image":"https://imgs.search.brave.com/tune.jpg"}]}"#
private let stockSource =
    #"{"symbol":"NASDAQ:AAPL","range":"1D","note":"Up 12% since the earnings call; the gap at Oct 2 is the split."}"#

private func step(_ i: Int, _ extra: [String: Any] = [:]) -> [String: Any] {
    ["text": "Step \(i)"].merging(extra) { $1 }
}
private func steps(_ extra: [String: Any] = [:]) -> String { json(["steps": [step(1), step(2)]].merging(extra) { $1 }) }
private func stock(_ extra: [String: Any] = [:]) -> String { json(["symbol": "NASDAQ:AAPL"].merging(extra) { $1 }) }

private let stepsCases: [(String, String, Bool)] = [
    ("the spec's example", stepsSource, true),
    ("two steps, no title", steps(), true),
    ("one step", steps(["steps": [step(1)]]), false),
    ("twelve steps", steps(["steps": (0..<12).map { step($0) }]), true),
    ("thirteen steps", steps(["steps": (0..<13).map { step($0) }]), false),
    ("a 300-character step", steps(["steps": [step(1, ["text": repeated("x", 300)]), step(2)]]), true),
    ("a 301-character step", steps(["steps": [step(1, ["text": repeated("x", 301)]), step(2)]]), false),
    ("150 emoji (300 UTF-16 units)", steps(["steps": [step(1, ["text": repeated("😀", 150)]), step(2)]]), true),
    ("151 emoji (302 UTF-16 units)", steps(["steps": [step(1, ["text": repeated("😀", 151)]), step(2)]]), false),
    ("a step on two lines", steps(["steps": [step(1, ["text": "a\nb"]), step(2)]]), false),
    ("an empty step", steps(["steps": [step(1, ["text": ""]), step(2)]]), false),
    ("an https picture", steps(["steps": [step(1, ["image": "https://imgs.search.brave.com/x.jpg"]), step(2)]]), true),
    ("an http picture", steps(["steps": [step(1, ["image": "http://example.com/x.jpg"]), step(2)]]), false),
    ("a data: picture", steps(["steps": [step(1, ["image": "data:image/png;base64,AAAA"]), step(2)]]), false),
    ("a picture URL with a space", steps(["steps": [step(1, ["image": "https://example.com/a b.jpg"]), step(2)]]), false),
    ("a 2048-character picture URL", steps(["steps": [step(1, ["image": "https://e.co/" + repeated("a", 2035)]), step(2)]]), true),
    ("a 2049-character picture URL", steps(["steps": [step(1, ["image": "https://e.co/" + repeated("a", 2036)]), step(2)]]), false),
    ("a 200-character title", steps(["title": repeated("t", 200)]), true),
    ("a 201-character title", steps(["title": repeated("t", 201)]), false),
    ("a title on two lines", steps(["title": "a\nb"]), false),
    ("an empty title (none)", steps(["title": ""]), true),
    ("nulls for what is optional", steps(["title": NSNull(), "steps": [step(1, ["image": NSNull()]), step(2)]]), true),
    ("keys it does not know", steps(["colour": "red"]), true),
    ("not JSON", #"{"steps":"#, false),
    ("an array", "[]", false),
]

private let stockCases: [(String, String, Bool)] =
    [
        ("the spec's example", stockSource, true),
        ("a symbol alone", stock(), true),
    ] + ["1D", "1M", "3M", "12M", "60M", "ALL"].map { ("the range \($0)", stock(["range": $0]), true) } + [
        ("a range it does not know (5D)", stock(["range": "5D"]), false),
        ("a lowercase range", stock(["range": "1d"]), false),
        ("a lowercase symbol", stock(["symbol": "nasdaq:aapl"]), false),
        ("a symbol without an exchange", stock(["symbol": "AAPL"]), false),
        ("a symbol with a space", stock(["symbol": "NASDAQ: AAPL"]), false),
        ("a symbol with a slash", stock(["symbol": "NASDAQ:AAPL/../X"]), false),
        ("a symbol with a dot and a dash", stock(["symbol": "TSE:7203.T-A"]), true),
        ("a 40-character symbol", stock(["symbol": "X:" + repeated("A", 38)]), true),
        ("a 41-character symbol", stock(["symbol": "X:" + repeated("A", 39)]), false),
        ("a 300-character note", stock(["note": repeated("n", 300)]), true),
        ("a 301-character note", stock(["note": repeated("n", 301)]), false),
        ("a note on two lines", stock(["note": "a\nb"]), true),
        ("nulls for what is optional", stock(["range": NSNull(), "note": NSNull()]), true),
        ("no symbol", json(["note": "x"]), false),
        ("an array", "[]", false),
    ]

private let findCases: [(String, String, InteractiveBlock.Kind?)] = [
    ("a questionnaire after a paragraph", "Intro\n\n```actovia-ask\n\(askSource)\n```\n\nAfter", .ask),
    ("a fence still open (a reply streaming)", "Intro\n\n```actovia-ask\n\(askSource)", nil),
    ("two blocks: only the first counts", "```actovia-confirm\n\(confirmSource)\n```\n\n```actovia-ask\n\(askSource)\n```", .confirm),
    ("a first block that does not validate: none", "```actovia-ask\n{oops}\n```\n\n```actovia-confirm\n\(confirmSource)\n```", nil),
    ("inside a longer backtick fence", "````md\n```actovia-ask\n\(askSource)\n```\n````", nil),
    ("inside a tilde fence", "~~~\n```actovia-ask\n\(askSource)\n```\n~~~", nil),
    ("indented under a list item", "- item\n\n  ```actovia-ask\n  \(askSource)\n  ```", nil),
    ("after an ordinary code block", "```js\nlet a = 1\n```\n\n```actovia-confirm\n\(confirmSource)\n```", .confirm),
    ("trailing spaces after the name", "```actovia-confirm  \n\(confirmSource)\n```", .confirm),
    ("after a line of inline code that looks like a fence", "Install it with\n```npm i```\n\n```actovia-confirm\n\(confirmSource)\n```", .confirm),
    ("a closing line with a no-break space after it: not a closer", "```actovia-confirm\n\(confirmSource)\n``` \u{00A0}", nil),
    ("an ideographic space after the name: another name", "```actovia-ask\u{3000}\n\(askSource)\n```", nil),
    ("a tab after the name and after the closing fence", "```actovia-confirm\t\n\(confirmSource)\n```\t", .confirm),
    ("CRLF line ends", "Intro\r\n\r\n```actovia-confirm \r\n\(confirmSource)\r\n```\r\n", .confirm),
    ("another name", "```actovia-answer\n{\"block\":\"ask\",\"ref\":\"r\"}\n```", nil),
    ("a steps block", "Here:\n\n```actovia-steps\n\(stepsSource)\n```", .steps),
    ("a stock block", "```actovia-stock\n\(stockSource)\n```", .stock),
    ("a stock block after a questionnaire: the questionnaire", "```actovia-ask\n\(askSource)\n```\n\n```actovia-stock\n\(stockSource)\n```", .ask),
    ("a stock block that does not validate, then steps: none", "```actovia-stock\n{\"symbol\":\"aapl\"}\n```\n\n```actovia-steps\n\(stepsSource)\n```", nil),
]

@Suite("InteractiveBlock: the blocks' limits, as the desktop's zod schemas")
struct InteractiveBlockTests {
    @Test("actovia-ask", arguments: askCases)
    func askLimits(_ name: String, _ source: String, _ valid: Bool) {
        #expect((InteractiveBlock.parse(.ask, source: source) != nil) == valid, "\(name)")
    }

    @Test("actovia-steps", arguments: stepsCases)
    func stepsLimits(_ name: String, _ source: String, _ valid: Bool) {
        #expect((InteractiveBlock.parse(.steps, source: source) != nil) == valid, "\(name)")
    }

    @Test("actovia-stock", arguments: stockCases)
    func stockLimits(_ name: String, _ source: String, _ valid: Bool) {
        #expect((InteractiveBlock.parse(.stock, source: source) != nil) == valid, "\(name)")
    }

    @Test("the parsed blocks keep their fields; a missing range is the default, 1D")
    func parsed() throws {
        guard case .steps(let steps)? = InteractiveBlock.parse(.steps, source: stepsSource) else { return #expect(Bool(false)) }
        #expect(steps.steps.count == 3)
        #expect(steps.steps[1].image == nil)
        guard case .stock(let full)? = InteractiveBlock.parse(.stock, source: stockSource) else { return #expect(Bool(false)) }
        #expect(full.range == .oneDay)
        guard case .stock(let bare)? = InteractiveBlock.parse(.stock, source: stock()) else { return #expect(Bool(false)) }
        #expect(bare.range == nil)
        #expect((bare.range ?? .default) == .oneDay)
        #expect(InteractiveBlock.Kind.steps.isAnswerable == false)
        #expect(InteractiveBlock.Kind.ask.isAnswerable)
    }

    @Test("actovia-confirm", arguments: confirmCases)
    func confirmLimits(_ name: String, _ source: String, _ valid: Bool) {
        #expect((InteractiveBlock.parse(.confirm, source: source) != nil) == valid, "\(name)")
    }

    @Test("a missing \"other\" is no Other; the fence's names map to kinds")
    func reading() throws {
        guard case .ask(let block)? = InteractiveBlock.parse(.ask, source: askSource) else {
            Issue.record("expected a questionnaire")
            return
        }
        #expect(block.questions.map(\.other) == [true, false])
        #expect(block.questions.map(\.type) == [.single, .multi])
        #expect(InteractiveBlock.Kind(language: "actovia-ask") == .ask)
        #expect(InteractiveBlock.Kind(language: "actovia-confirm") == .confirm)
        #expect(InteractiveBlock.Kind(language: "actovia-answer") == nil)
        #expect(InteractiveBlock.Kind.confirm.language == "actovia-confirm")
    }
}

@Suite("InteractiveFence: which fence of a reply is its block")
struct InteractiveFenceTests {
    @Test("find", arguments: findCases)
    func find(_ name: String, _ markdown: String, _ kind: InteractiveBlock.Kind?) {
        #expect(InteractiveFence.first(in: markdown)?.kind == kind, "\(name)")
    }

    @Test("the fence's text is how its code block is known")
    func matches() throws {
        let fence = try #require(InteractiveFence.first(in: "Intro\n\n```actovia-ask\n\(askSource)\n```\n"))
        #expect(fence.source == askSource)
        #expect(fence.matches(language: "actovia-ask", code: askSource))
        #expect(fence.matches(language: "actovia-ask", code: askSource + "\n"))
        #expect(!fence.matches(language: "actovia-confirm", code: askSource))
        #expect(!fence.matches(language: nil, code: askSource))
        #expect(!fence.matches(language: "actovia-ask", code: "{}"))
    }
}
