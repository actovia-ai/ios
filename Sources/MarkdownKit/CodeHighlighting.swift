import Foundation
import HighlightSwift
import SwiftUI

/// Xcode's Default (Light) and Default (Dark) colours — read from Xcode.app's own `FontAndColorThemes` — as
/// highlight.js CSS, the same mapping the desktop's `markdown/code-themes.ts` uses, so both apps colour a block
/// alike. highlight.js cannot tell a project symbol from a system one: a declared class or function takes Xcode's
/// declaration colours, a built-in type the system colour, a plain title or variable the project colour.
enum CodeHighlightPalette {
    struct Colours {
        let keyword, string, number, comment, docKeyword: String
        let declarationType, declarationOther, typeSystem, classProject, functionProject, variableProject: String
        let preprocessor, attribute, url, markupCode: String
    }

    static let light = Colours(
        keyword: "#9B2393", string: "#C41A16", number: "#1C00CF", comment: "#5D6C79", docKeyword: "#4A5560",
        declarationType: "#0B4F79", declarationOther: "#0F68A0", typeSystem: "#3900A0", classProject: "#1C464A",
        functionProject: "#326D74", variableProject: "#326D74", preprocessor: "#643820", attribute: "#815F03",
        url: "#0E0EFF", markupCode: "#AA0D91")

    static let dark = Colours(
        keyword: "#FC5FA3", string: "#FC6A5D", number: "#D0BF69", comment: "#6C7986", docKeyword: "#92A1B1",
        declarationType: "#5DD8FF", declarationOther: "#41A1C0", typeSystem: "#D0A8FF", classProject: "#9EF1DD",
        functionProject: "#67B7A4", variableProject: "#67B7A4", preprocessor: "#FD8F3F", attribute: "#BF8555",
        url: "#5482FF", markupCode: "#AA0D91")

    static func css(for scheme: ColorScheme) -> String {
        css(scheme == .dark ? dark : light)
    }

    /// No background and no base colour: the block's fill and the chat's text colour are the view's.
    static func css(_ c: Colours) -> String {
        """
        .hljs{background:transparent}
        .hljs-keyword,.hljs-literal,.hljs-tag,.hljs-name,.hljs-selector-tag,.hljs-bullet{color:\(c.keyword)}
        .hljs-string,.hljs-regexp,.hljs-char{color:\(c.string)}
        .hljs-code{color:\(c.markupCode)}
        .hljs-number,.hljs-symbol{color:\(c.number)}
        .hljs-comment,.hljs-quote{color:\(c.comment)}
        .hljs-doctag{color:\(c.docKeyword);font-weight:600}
        .hljs-title.class_{color:\(c.declarationType)}
        .hljs-title.function_{color:\(c.declarationOther)}
        .hljs-type,.hljs-built_in{color:\(c.typeSystem)}
        .hljs-title{color:\(c.functionProject)}
        .hljs-selector-class,.hljs-selector-id{color:\(c.classProject)}
        .hljs-variable,.hljs-template-variable,.hljs-property,.hljs-params{color:\(c.variableProject)}
        .hljs-meta{color:\(c.preprocessor)}
        .hljs-attr,.hljs-attribute{color:\(c.attribute)}
        .hljs-link{color:\(c.url);text-decoration:underline}
        .hljs-emphasis{font-style:italic}
        .hljs-strong,.hljs-section{font-weight:600}
        """
    }
}

/// Colours a code block through highlight.js (HighlightSwift runs it in JavaScriptCore) — the desktop's tokenizer,
/// so a block reads the same on both. One shared instance, results kept by (code, language, scheme) so a block the
/// transcript draws again, or a streaming reply that re-renders every token, does not go through JavaScript twice.
/// Fonts the HTML import brings along are stripped: the view sets the monospaced font at the user's text size.
actor CodeHighlighter {
    static let shared = CodeHighlighter()

    /// Past this the block is drawn plain: a pasted log is not worth the JavaScript round-trip.
    static let maximumLength = 20_000

    private let highlight = Highlight()
    private var cache: [Key: AttributedString] = [:]
    private var order: [Key] = []
    private let capacity = 200

    struct Key: Hashable {
        let code: String
        let language: String?
        let dark: Bool
    }

    /// The coloured text, or nil when the block is too long, the language unknown to highlight.js, or JavaScript
    /// failed — the caller then draws the plain code.
    func attributed(code: String, language: String?, scheme: ColorScheme) async -> AttributedString? {
        guard code.count <= Self.maximumLength else { return nil }
        let key = Key(code: code, language: language, dark: scheme == .dark)
        if let hit = cache[key] { return hit }
        let colours = HighlightColors.custom(css: CodeHighlightPalette.css(for: scheme))
        var result: AttributedString
        do {
            if let language, !language.isEmpty {
                result = try await highlight.attributedText(code, language: language, colors: colours)
            } else {
                result = try await highlight.attributedText(code, colors: colours)
            }
        } catch {
            return nil
        }
        // A plain-text echo (unknown language, nothing to colour) is not worth keeping or drawing.
        guard result.runs.count > 1 else { return nil }
        Self.stripFonts(&result)
        remember(key, result)
        return result
    }

    /// The HTML import sets a serif font and a background on every run; the view owns both.
    static func stripFonts(_ text: inout AttributedString) {
        text.font = nil
        text.backgroundColor = nil
        #if canImport(UIKit)
            text.uiKit.font = nil
            text.uiKit.backgroundColor = nil
        #endif
    }

    private func remember(_ key: Key, _ value: AttributedString) {
        if cache[key] == nil {
            order.append(key)
            if order.count > capacity, let oldest = order.first {
                order.removeFirst()
                cache[oldest] = nil
            }
        }
        cache[key] = value
    }
}
