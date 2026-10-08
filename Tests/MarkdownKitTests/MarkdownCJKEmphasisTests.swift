import Foundation
import Testing

@testable import MarkdownKit

/// CommonMark's flanking rule leaves `而是**"引号"**` literal: a `**` after a letter and before punctuation does not
/// open, and CJK puts no space before a word. The CJK-friendly amendment the desktop renders with counts a CJK
/// character beside punctuation as the boundary a space is (github.com/tats-u/markdown-cjk-friendly).
@Suite("Markdown emphasis beside CJK text")
struct MarkdownCJKEmphasisTests {
    private func content(_ text: String) -> AttributedString? {
        guard case .paragraph(let content) = MarkdownParser.parse(text).first?.kind else { return nil }
        return content
    }

    private func strong(_ text: String) -> [String] {
        guard let content = content(text) else { return [] }
        return MarkdownFixtures.runs(content).filter { $0.intent.contains(.stronglyEmphasized) }.map(\.text)
    }

    private func plain(_ text: String) -> String {
        content(text).map(MarkdownFixtures.plain) ?? ""
    }

    @Test("a quotation after a CJK letter is bold", arguments: [
        ("而是**\"卖与不卖都没有依据\"**——赢家", "\"卖与不卖都没有依据\"", "而是\"卖与不卖都没有依据\"——赢家"),
        ("而是**“卖与不卖都没有依据”**——赢家", "“卖与不卖都没有依据”", "而是“卖与不卖都没有依据”——赢家"),
        ("这是**「重点」**的说法", "「重点」", "这是「重点」的说法"),
    ])
    func quotation(input: String, bold: String, shown: String) {
        #expect(strong(input) == [bold])
        #expect(plain(input) == shown)
    }

    @Test("bold that ends in CJK punctuation, or is followed by it")
    func punctuation() {
        #expect(strong("**粗体**。后面") == ["粗体"])
        #expect(strong("前面**粗体。**后面") == ["粗体。"])
        #expect(plain("前面**粗体。**后面") == "前面粗体。后面")
    }

    @Test("bold closes after CJK punctuation though a digit or a Latin letter follows, and opens before it")
    func fullWidthPunctuation() {
        #expect(strong("**三、地理与性别的再平衡。**2018 年以来男女严格交替") == ["三、地理与性别的再平衡。"])
        #expect(plain("**三、地理与性别的再平衡。**2018 年") == "三、地理与性别的再平衡。2018 年")
        #expect(strong("**结论：**Carson 获奖") == ["结论："])
        #expect(strong("2018**「女性年」**之后") == ["「女性年」"])
        // Half-width punctuation keeps CommonMark's rule.
        #expect(strong("**bold.**2018").isEmpty)
    }

    @Test("bold and italics inside a CJK sentence")
    func inSentence() {
        #expect(strong("中文**粗体**中文") == ["粗体"])
        guard let content = content("中文*斜体*中文") else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(MarkdownFixtures.runs(content).filter { $0.intent.contains(.emphasized) }.map(\.text) == ["斜体"])
    }

    @Test("English emphasis and literal asterisks are as CommonMark has them")
    func latin() {
        #expect(strong("some **bold** text") == ["bold"])
        #expect(strong("a**\"quoted\"**b").isEmpty)
        #expect(plain("a**\"quoted\"**b") == "a**\"quoted\"**b")
        #expect(plain("2 * 3 * 4") == "2 * 3 * 4")
    }

    @Test("asterisks in code are left as they are")
    func code() {
        guard let content = content("用 `**\"x\"**` 表示") else {
            Issue.record("expected a paragraph")
            return
        }
        #expect(MarkdownFixtures.runs(content).contains { $0.text == "**\"x\"**" && $0.intent.contains(.code) })
        guard case .codeBlock(_, let code) = MarkdownParser.parse("```\n而是**\"引号\"**\n```").first?.kind else {
            Issue.record("expected a code block")
            return
        }
        #expect(code == "而是**\"引号\"**")
    }

    @Test("the boundary it inserts is never shown")
    func noMarkerLeft() {
        #expect(!plain("而是**\"引号\"**赢家").contains("\u{2063}"))
        #expect(MarkdownPreprocessor.cjkEmphasis("plain text") == "plain text")
    }
}
