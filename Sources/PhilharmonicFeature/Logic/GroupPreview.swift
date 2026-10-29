import Foundation
import MarkdownKit

/// A group's last message as the drawer's one-line preview: the words it says, as Chat shows someone else's text small
/// (ISSUE-286). Markdown comes off through `MarkdownPlainText` (emphasis, links, code, headings, escapes); what a
/// model escaped on purpose — `\*\*Saihō-ji`, read back as a literal `**` — is still markup to a reader, so a run of
/// two or more `*` or `_` goes too.
enum GroupPreview {
    /// Enough for one line however wide the drawer; a long report is not parsed whole for a preview.
    static let sourceLimit = 2_000

    static func text(_ content: String) -> String {
        let plain = MarkdownPlainText.strip(String(content.prefix(sourceLimit)))
        let unmarked = plain.replacingOccurrences(of: #"[*_]{2,}"#, with: "", options: .regularExpression)
        return unmarked.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
