import Foundation

/// What leaves the app as words — Copy, read-aloud — of a reply that holds a steps or stock block (spec 2026-10-07
/// §4): the list a reader would say, the symbol and its reading, in place of the fence's JSON. The questionnaire and
/// the confirmation are left as they are, as in phase 1. The desktop's `interactive-plain-text.ts` writes the same
/// strings, held to the same vectors.
enum InteractivePlainText {
    /// The block's words, or nil for a kind that has none here.
    static func text(of block: InteractiveBlock) -> String? {
        switch block {
        case .steps(let steps):
            let list = steps.steps.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
            let title = steps.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? list : title + "\n\n" + list
        case .stock(let stock):
            let note = stock.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return note.isEmpty ? stock.symbol : stock.symbol + " \u{2014} " + note
        case .ask, .confirm:
            return nil
        }
    }

    /// The reply with its block's fence — the lines from ```` ```exodus-… ```` to the closing ```` ``` ```` — replaced by
    /// the block's words; the reply as it was (line ends made `\n`) when it holds no such block.
    static func replacingBlock(in markdown: String) -> String {
        let normalized = JSText.string(JSText.unixLines(markdown))
        guard let fence = InteractiveFence.first(in: normalized), let words = text(of: fence.block) else {
            return normalized
        }
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard fence.line < lines.count, fence.closingLine < lines.count else { return normalized }
        lines.replaceSubrange(fence.line...fence.closingLine, with: [words])
        return lines.joined(separator: "\n")
    }
}
