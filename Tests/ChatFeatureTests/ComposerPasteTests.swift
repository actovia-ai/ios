import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import ChatFeature

/// What a paste into the composer adds as pictures (ISSUE-299: a screenshot copied on the Mac came in as its name).
struct ComposerPasteTests {
    private let png = PictureFixture.data(width: 4, height: 4, png: true)

    @Test func aScreenshotFromTheMacIsItsPictureNotItsName() {
        let items: [[String: Any]] = [[
            UTType.png.identifier: png,
            UTType.utf8PlainText.identifier: "Screenshot 2026-10-29 at 20.53.57"
        ]]
        #expect(ComposerPaste.imageData(from: items) == [png])
    }

    @Test func onePicturePerItem() {
        let jpeg = PictureFixture.data(width: 4, height: 4)
        let items: [[String: Any]] = [[UTType.png.identifier: png], [UTType.jpeg.identifier: jpeg]]
        #expect(ComposerPaste.imageData(from: items) == [png, jpeg])
    }

    @Test func aUIImageIsReencoded() throws {
        let image = try #require(UIImage(data: png))
        let data = ComposerPaste.imageData(from: [[UTType.image.identifier: image]])
        #expect(data.count == 1)
        #expect(UIImage(data: data[0]) != nil)
    }

    @Test func textAloneIsNoPicture() {
        let items: [[String: Any]] = [[UTType.utf8PlainText.identifier: "hello"]]
        #expect(ComposerPaste.imageData(from: items).isEmpty)
    }
}

/// The field itself, on a private pasteboard.
@MainActor
@Suite(.serialized)
struct ComposerTextViewPasteTests {
    private let png = PictureFixture.data(width: 4, height: 4, png: true)

    private func field(onPaste: @escaping ([Data]) -> Void) -> PastingTextView {
        let view = PastingTextView.composerField()
        view.onPasteImages = onPaste
        return view
    }

    @Test func pastingAScreenshotAddsItAndTypesNothing() {
        // A private pasteboard: the general one, read outside a person's paste, puts up "Allow Paste".
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }
        board.items = [[
            UTType.png.identifier: png,
            UTType.utf8PlainText.identifier: "Screenshot 2026-10-29 at 20.53.57"
        ]]
        var pasted: [Data] = []
        let view = field { pasted = $0 }
        view.pasteboard = board
        #expect(view.canPerformAction(#selector(UIResponder.paste(_:)), withSender: nil))
        view.paste(nil)
        #expect(pasted == [png])
        #expect(view.text.isEmpty)
    }

    @Test func itGrowsALineAtATimeUpToFiveThenScrolls() throws {
        let view = field { _ in }
        let line = try #require(view.font?.lineHeight)
        func height(_ text: String) -> CGFloat {
            view.text = text
            return ComposerTextView.height(of: view, width: 240, maxLines: 5).height
        }
        #expect(abs(height("") - ceil(line)) <= 1)
        #expect(abs(height("one") - ceil(line)) < 2)
        #expect(height("1\n2\n3") > line * 2.5)
        #expect(abs(height((1...12).map(String.init).joined(separator: "\n")) - ceil(line * 5)) < 1)
        #expect(ComposerTextView.height(of: view, width: 240, maxLines: 5).scrolls)
    }
}
