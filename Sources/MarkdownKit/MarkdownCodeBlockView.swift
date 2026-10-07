import SwiftUI
import UIKit

/// The shape of a block that is set apart from the text around it — code, a table, an image's frame: a quiet
/// fill, no edge, the transcript cards' continuous corner a step smaller.
enum MarkdownBlockShape {
    static let radius: CGFloat = 14
    static let inset: CGFloat = 14
    static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
}

struct MarkdownCodeBlockView: View {
    let language: String?
    let code: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?
    /// The coloured code, for exactly `code` in exactly this scheme; plain until it arrives, or when there is none.
    @State private var highlighted: Highlighted?

    private struct Highlighted: Equatable {
        let code: String
        let dark: Bool
        let text: AttributedString
    }

    /// The panel's fill: a grey with no colour in it, the desktop's `--code` (0.97 / 0.269 in oklch). The system's
    /// `secondarySystemBackground` has a blue cast (#F2F2F7) that read as the colour tone's beside a toned bubble
    /// (owner, 2026-10-08); a code block keeps out of the tone in every scheme.
    static let panel = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white: 0.13, alpha: 1) : UIColor(white: 0.96, alpha: 1)
        })

    /// The symbol, not a word: a symbol name is never localized.
    private var copySymbol: String {
        if copied { return "checkmark" }
        return "doc.on.doc"
    }

    private var codeFont: Font {
        // A step under the inline code's size (footnote, 13 pt at the default size): monospaced at subheadline read
        // large in a block (owner, 2026-10-08); it still scales with the reader's text size.
        .system(size: MarkdownFontSpec(style: .footnote).pointSize, design: .monospaced)
    }

    /// What the block draws: the highlight when it is for this very text, the plain code otherwise.
    private var displayedText: AttributedString {
        if let highlighted, highlighted.code == code, highlighted.dark == (colorScheme == .dark) {
            return highlighted.text
        }
        return AttributedString(code)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let language {
                    // The desktop's strip: a code glyph and the language as its makers spell it, at the
                    // subheadline size — caption read too small over code (owner, 2026-10-08).
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(verbatim: MarkdownLanguageName.display(language))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                // The icon alone, in a box of one size: a label that read "Copy" and then "Copied" changed width and
                // shook the strip; the word is still there for VoiceOver, and the symbol morphs in place.
                Button(action: copy) {
                    Label {
                        if copied {
                            Text("ios:chat.markdown.codeCopied")
                        } else {
                            Text("ios:chat.markdown.copyCode")
                        }
                    } icon: {
                        Image(systemName: copySymbol)
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
                .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, MarkdownBlockShape.inset)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView(.horizontal) {
                Text(displayedText)
                    .font(codeFont)
                    .fixedSize(horizontal: true, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, MarkdownBlockShape.inset)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .markdownTrailingFade()
        }
        .background(Self.panel, in: MarkdownBlockShape.shape)
        // Colour the code off the main actor (highlight.js in JavaScriptCore), again when the text or the scheme
        // changes — a streaming block re-renders every token, so the highlighter caches by (code, language, scheme).
        .task(id: HighlightRequest(code: code, language: language, dark: colorScheme == .dark)) {
            let dark = colorScheme == .dark
            let text = await CodeHighlighter.shared.attributed(code: code, language: language, scheme: colorScheme)
            guard !Task.isCancelled else { return }
            highlighted = text.map { Highlighted(code: code, dark: dark, text: $0) }
        }
    }

    private struct HighlightRequest: Equatable {
        let code: String
        let language: String?
        let dark: Bool
    }

    private func copy() {
        UIPasteboard.general.string = code
        copied = true
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copied = false
        }
    }
}
