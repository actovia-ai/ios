import Foundation
import SwiftUI

/// Marks each word of a search query inside a result's title or snippet.
enum SearchHighlight {
    /// `text` with every case- and diacritic-insensitive occurrence of each whitespace-separated word
    /// of `query` set bold (keeping the size of the text around it) and primary, so it stands out from the muted snippet around it.
    static func attributed(_ text: String, query: String) -> AttributedString {
        var result = AttributedString(text)
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        for word in words {
            var searchRange = text.startIndex..<text.endIndex
            while let match = text.range(
                of: word, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            {
                if let target = Range(match, in: result) {
                    result[target].inlinePresentationIntent = .stronglyEmphasized
                    result[target].foregroundColor = .primary
                }
                searchRange = match.upperBound..<text.endIndex
            }
        }
        return result
    }
}
