import Testing

@testable import ChatFeature

// The same vectors as the desktop's tests/unit/shared/utils/interactive-plain-text.test.ts — keep them in step.
private let steps =
    #"{"title":"Replacing the strings","steps":[{"text":"Loosen the old string.","image":"https://imgs.search.brave.com/peg.jpg"},{"text":"Thread the new one."}]}"#
private let stock = #"{"symbol":"NASDAQ:AAPL","range":"1D","note":"Up 12% since the call."}"#
private let ask = #"{"title":"T","questions":[{"id":"a","text":"Q?","type":"single","options":["x","y"]}]}"#

private let cases: [(String, String, String)] = [
    ("steps become a titled numbered list", "Here is how:\n\n```exodus-steps\n\(steps)\n```\n\nGood luck.",
     "Here is how:\n\nReplacing the strings\n\n1. Loosen the old string.\n2. Thread the new one.\n\nGood luck."),
    ("steps without a title", "```exodus-steps\n{\"steps\":[{\"text\":\"A\"},{\"text\":\"B\"}]}\n```", "1. A\n2. B"),
    ("a stock block is its symbol and note", "```exodus-stock\n\(stock)\n```", "NASDAQ:AAPL — Up 12% since the call."),
    ("a stock block without a note is its symbol", "```exodus-stock\n{\"symbol\":\"NASDAQ:AAPL\"}\n```", "NASDAQ:AAPL"),
    ("CRLF line ends are made LF", "Intro\r\n\r\n```exodus-stock\r\n\(stock)\r\n```\r\n", "Intro\n\nNASDAQ:AAPL — Up 12% since the call.\n"),
    ("a questionnaire is left as it is", "```exodus-ask\n\(ask)\n```", "```exodus-ask\n\(ask)\n```"),
    ("a second block is code and stays", "```exodus-stock\n\(stock)\n```\n\n```exodus-steps\n\(steps)\n```",
     "NASDAQ:AAPL — Up 12% since the call.\n\n```exodus-steps\n\(steps)\n```"),
    ("a reply without a block is untouched", "Just words.\n\n```js\nlet a = 1\n```", "Just words.\n\n```js\nlet a = 1\n```"),
    ("a block that does not validate stays code", "```exodus-stock\n{\"symbol\":\"aapl\"}\n```", "```exodus-stock\n{\"symbol\":\"aapl\"}\n```"),
]

@Suite("InteractivePlainText: Copy and read-aloud get a block's words")
struct InteractivePlainTextTests {
    @Test("replacingBlock", arguments: cases)
    func replacing(_ name: String, _ markdown: String, _ text: String) {
        #expect(InteractivePlainText.replacingBlock(in: markdown) == text, "\(name)")
    }

    @Test("read-aloud speaks the words, not the JSON")
    func speech() {
        let prose = SpeechText.prose("Here:\n\n```exodus-stock\n\(stock)\n```")
        #expect(prose.contains("NASDAQ:AAPL — Up 12% since the call."))
        #expect(!prose.contains("exodus-stock"))
    }
}
