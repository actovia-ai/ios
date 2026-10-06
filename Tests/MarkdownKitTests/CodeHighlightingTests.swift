import SwiftUI
import Testing

@testable import MarkdownKit

@Suite("A code block's language name")
struct MarkdownLanguageNameTests {
    @Test("spells the known ones as their makers do, whatever the fence used")
    func known() {
        #expect(MarkdownLanguageName.display("css") == "CSS")
        #expect(MarkdownLanguageName.display("typescript") == "TypeScript")
        #expect(MarkdownLanguageName.display("ts") == "TypeScript")
        #expect(MarkdownLanguageName.display("tsx") == "TSX")
        #expect(MarkdownLanguageName.display("js") == "JavaScript")
        #expect(MarkdownLanguageName.display("json") == "JSON")
        #expect(MarkdownLanguageName.display("py") == "Python")
        #expect(MarkdownLanguageName.display("sh") == "Shell")
        #expect(MarkdownLanguageName.display("objc") == "Objective-C")
        #expect(MarkdownLanguageName.display("cpp") == "C++")
        #expect(MarkdownLanguageName.display("cs") == "C#")
        #expect(MarkdownLanguageName.display("swift") == "Swift")
    }

    @Test("is not fooled by case or spaces, and keeps an unknown name with a capital first letter")
    func caseAndUnknown() {
        #expect(MarkdownLanguageName.display("TypeScript") == "TypeScript")
        #expect(MarkdownLanguageName.display(" CSS ") == "CSS")
        #expect(MarkdownLanguageName.display("exodus-ask") == "Exodus-ask")
        #expect(MarkdownLanguageName.display("foo") == "Foo")
        #expect(MarkdownLanguageName.display("") == "")
    }
}

@Suite("Code highlighting")
struct CodeHighlightingTests {
    @Test("the palette CSS carries Xcode's keyword colour for each scheme, and no background or base colour of its own")
    func palette() {
        let light = CodeHighlightPalette.css(for: .light)
        let dark = CodeHighlightPalette.css(for: .dark)
        #expect(light.contains("#9B2393"))
        #expect(dark.contains("#FC5FA3"))
        #expect(light.contains(".hljs{background:transparent;color:\(CodeHighlightPalette.sentinel)}"))
        #expect(!light.contains(".hljs{color"))
        // Every class both apps map is present.
        for cls in [".hljs-keyword", ".hljs-string", ".hljs-number", ".hljs-comment", ".hljs-title.class_", ".hljs-built_in", ".hljs-meta", ".hljs-attr"] {
            #expect(light.contains(cls), "\(cls) missing")
        }
    }

    @Test("a Swift snippet comes back coloured in more than one run, its text unchanged, and the import's fonts stripped")
    func highlightsSwift() async {
        let code = "let answer: Int = 42 // the answer\nprint(\"hi\")"
        let text = await CodeHighlighter.shared.attributed(code: code, language: "swift", scheme: .light)
        let result = try? #require(text)
        guard let result else { return }
        #expect(String(result.characters) == code)
        #expect(result.runs.count > 1)
        for run in result.runs {
            #expect(run.font == nil)
            #expect(run.uiKit.font == nil)
        }
        // Plain code (the ` = ` between name and value) has no colour of its own, so the chat's text
        // colour shows through; `let` is a keyword and keeps Xcode's; nothing keeps the sentinel.
        #expect(result.runs.contains { $0.uiKit.foregroundColor == nil })
        let keyword = result.runs.first { String(result[$0.range].characters) == "let" }
        #expect(keyword?.uiKit.foregroundColor != nil)
        #expect(!result.runs.contains { run in run.uiKit.foregroundColor.map(CodeHighlighter.isSentinel) ?? false })
    }

    @Test("the same block is served from the cache, and an over-long one is left plain")
    func cacheAndCap() async {
        let code = "const x = 1"
        let first = await CodeHighlighter.shared.attributed(code: code, language: "ts", scheme: .dark)
        let second = await CodeHighlighter.shared.attributed(code: code, language: "ts", scheme: .dark)
        #expect(first != nil)
        #expect(first == second)
        let long = String(repeating: "x", count: CodeHighlighter.maximumLength + 1)
        #expect(await CodeHighlighter.shared.attributed(code: long, language: "ts", scheme: .dark) == nil)
    }

    @Test("an unknown language falls back to plain (nil), never to an error")
    func unknownLanguage() async {
        let text = await CodeHighlighter.shared.attributed(code: "hello world", language: "exodus-ask", scheme: .light)
        #expect(text == nil)
    }
}
