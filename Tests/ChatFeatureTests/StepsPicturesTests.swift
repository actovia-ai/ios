import Foundation
import Models
import Testing

@testable import ChatFeature

/// A run's search, as its tool result carries it: a page with a thumbnail, and an image result with an original and
/// a thumbnail.
private func sources() throws -> [CitationSource] {
    let json = #"""
        [{"rank":1,"link":"https://guitars.example/strings","title":"Restringing","snippet":"","hostname":"guitars.example",
          "thumbnail":"https://imgs.search.brave.com/peg.jpg",
          "media":[{"kind":"image","title":"bridge","url":"https://cdn.example.com/original/bridge.jpg","sourceUrl":"https://guitars.example/strings","thumbnailUrl":"https://imgs.search.brave.com/bridge-thumb.jpg"}]},
         {"rank":2,"link":"https://other.example/a","title":"Other","snippet":"","hostname":"other.example"}]
        """#
    let values = try JSONDecoder().decode([JSONValue].self, from: Data(json.utf8))
    return values.compactMap(CitationSource.init)
}

private func step(_ image: String?) -> InteractiveBlock.Steps.Step {
    let source = image.map { #"{"text":"S","image":"\#($0)"}"# } ?? #"{"text":"S"}"#
    return try! JSONDecoder().decode(InteractiveBlock.Steps.Step.self, from: Data(source.utf8))
}

@Suite("StepsPictures: a step's picture is one of the run's search thumbnails, or nothing")
struct StepsPicturesTests {
    @Test("thumbnails are pictures; an original, an unknown URL, http and no image are not")
    func pictures() throws {
        let sources = try sources()
        let media = sources.flatMap { $0.media.compactMap(WebSearchMedia.init(json:)) }
        #expect(media.count == 1)
        let pictures = StepsPictures(sources: sources, media: media)
        #expect(pictures.url(for: step("https://imgs.search.brave.com/peg.jpg"))?.absoluteString == "https://imgs.search.brave.com/peg.jpg")
        #expect(pictures.url(for: step("https://imgs.search.brave.com/bridge-thumb.jpg")) != nil)
        // The image result's original: not a thumbnail, not drawn.
        #expect(pictures.url(for: step("https://cdn.example.com/original/bridge.jpg")) == nil)
        #expect(pictures.url(for: step("https://imgs.search.brave.com/not-from-this-run.jpg")) == nil)
        #expect(pictures.url(for: step("http://imgs.search.brave.com/peg.jpg")) == nil)
        #expect(pictures.url(for: step(nil)) == nil)
    }

    @Test("a run that searched nothing has no pictures")
    func none() {
        #expect(StepsPictures(sources: [], media: []).url(for: step("https://imgs.search.brave.com/peg.jpg")) == nil)
        #expect(StepsPictures().urls.isEmpty)
    }
}
