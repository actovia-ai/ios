import CoreGraphics
import Testing

@testable import ChatFeature

/// Whether the end of the transcript is in view: it decides the scroll-to-end button, and whether a streaming reply
/// is followed.
struct TranscriptEndTests {
    // A 600 pt screen whose bottom 100 pt are the composer's bar, over 2000 pt of transcript.
    private func distance(offset: CGFloat) -> CGFloat {
        TranscriptEnd.distance(contentHeight: 2000, offsetY: offset, containerHeight: 600, bottomInset: 100)
    }

    @Test func scrolledAllTheWayDownIsAtTheEnd() {
        // The furthest a scroll view goes: its content plus the inset, less the screen.
        #expect(distance(offset: 1500) == 0)
        #expect(TranscriptEnd.isAtEnd(distance: distance(offset: 1500)))
    }

    @Test func aLittleAboveTheEndStillCounts() {
        #expect(TranscriptEnd.isAtEnd(distance: distance(offset: 1500 - TranscriptEnd.slack + 1)))
    }

    @Test func scrolledUpIsNotAtTheEnd() {
        #expect(!TranscriptEnd.isAtEnd(distance: distance(offset: 1000)))
        #expect(!TranscriptEnd.isAtEnd(distance: distance(offset: 0)))
    }

    @Test func aTranscriptShorterThanTheScreenIsAlwaysAtTheEnd() {
        let short = TranscriptEnd.distance(contentHeight: 300, offsetY: 0, containerHeight: 600, bottomInset: 100)
        #expect(TranscriptEnd.isAtEnd(distance: short))
    }

    @Test func pastTheEndInABounceIsAtTheEnd() {
        #expect(TranscriptEnd.isAtEnd(distance: distance(offset: 1560)))
    }

    /// Measured in the Simulator at the end of the message gallery (iPhone, composer bar up): `visibleRect` is the
    /// whole 874 pt screen, the bottom inset the composer's bar. Reading the screen as `containerSize` (639 pt, the
    /// bars taken off) counted the bar twice and showed the button at the very end.
    @Test func theMeasuredEndOfTheGalleryIsAtTheEnd() {
        let end = TranscriptEnd.distance(
            contentHeight: 4370, offsetY: 3614.67, containerHeight: 874, bottomInset: 118.67)
        #expect(abs(end) < 1)
        #expect(TranscriptEnd.isAtEnd(distance: end))
    }
}
