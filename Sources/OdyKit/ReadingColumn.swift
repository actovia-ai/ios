import SwiftUI

/// The one rule for a wide screen — an unfolded iPhone Duo, landscape: what is read keeps a readable line length in a
/// centred column, and what holds it (a scroll view, a page's background) still spans the screen, so it scrolls from
/// anywhere. On a phone the column is wider than the screen and changes nothing. Claude's app on the Duo is the
/// reference (owner, 2026-10-23): the sidebar docked on the left, the conversation centred beside it.
public enum ReadingColumn {
    /// A chat's transcript and composer.
    public static let width: CGFloat = 680
    /// From this width the drawer's sidebar is docked beside the content instead of sliding over it.
    public static let dockedSidebarFrom: CGFloat = 700
    /// The docked sidebar's width.
    public static let sidebarWidth: CGFloat = 300
}

extension View {
    /// Centres the view in a column at most `width` wide.
    public func readingColumn(_ width: CGFloat = ReadingColumn.width) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}
