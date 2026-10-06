import SwiftUI

/// Whether the end of a transcript is in view. Out of view, a button over the composer goes back to it, and a reply
/// streaming in is no longer followed — whoever scrolled up is reading, as on the desktop.
enum TranscriptEnd {
    /// This close to the end still counts as there: the last line of a streaming reply grows past it by a few points
    /// between frames, and a bounce overshoots.
    static let slack: CGFloat = 80

    /// How far the end is below what is on screen: the content and the room kept under it for the composer's bar,
    /// less the bottom of the screen. Negative in a bounce past the end, or when everything fits.
    static func distance(
        contentHeight: CGFloat, offsetY: CGFloat, containerHeight: CGFloat, bottomInset: CGFloat
    ) -> CGFloat {
        contentHeight + bottomInset - (offsetY + containerHeight)
    }

    static func isAtEnd(distance: CGFloat) -> Bool { distance <= slack }

    /// `visibleRect` is the whole screen, bars included, in content coordinates; `containerSize` is not (it is the
    /// screen less the bars' insets), so the screen is read from the former.
    static func isAtEnd(_ geometry: ScrollGeometry) -> Bool {
        isAtEnd(
            distance: distance(
                contentHeight: geometry.contentSize.height, offsetY: geometry.visibleRect.minY,
                containerHeight: geometry.visibleRect.height, bottomInset: geometry.contentInsets.bottom))
    }
}

/// The way back to the end of the transcript: a round glass button, centred over the composer.
struct TranscriptEndButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("chat:messageList.scrollToBottom", systemImage: "arrow.down")
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityIdentifier("scrollToEnd")
    }
}

extension View {
    /// Tracks whether the transcript's end is in view, and shows `TranscriptEndButton` over the bottom of the
    /// scroll view while it is not. `isAtEnd` is the caller's, so it can also decide whether to follow a reply.
    func transcriptEnd(isAtEnd: Binding<Bool>, scrollToEnd: @escaping () -> Void) -> some View {
        modifier(TranscriptEndModifier(isAtEnd: isAtEnd, scrollToEnd: scrollToEnd))
    }
}

private struct TranscriptEndModifier: ViewModifier {
    @Binding var isAtEnd: Bool
    let scrollToEnd: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self, of: TranscriptEnd.isAtEnd) { _, atEnd in
                isAtEnd = atEnd
            }
            .overlay(alignment: .bottom) {
                if !isAtEnd {
                    TranscriptEndButton(action: scrollToEnd)
                        .padding(.bottom, 12)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: isAtEnd)
    }
}
