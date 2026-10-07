import Models
import SwiftUI
import UIKit

/// The thumbnails a run's search returned — a page's thumbnail, a media result's thumbnail — and nothing else: what
/// a step's picture may be. A media result's original `url`, which `SearchGallery.trustedURLs` admits for the
/// gallery, is left out on purpose: an original is a hot-link the source site may refuse or swap (owner, 2026-10-07).
struct StepsPictures: Equatable, Sendable {
    let urls: Set<URL>

    init(urls: Set<URL> = []) { self.urls = urls }

    init(sources: [CitationSource], media: [WebSearchMedia]) {
        var urls: Set<URL> = []
        for source in sources {
            if let thumbnail = source.thumbnail, let url = SearchMediaPolicy.fetchableURL(thumbnail) { urls.insert(url) }
        }
        for item in media {
            if let thumbnail = item.thumbnailUrl, let url = SearchMediaPolicy.fetchableURL(thumbnail) { urls.insert(url) }
        }
        self.urls = urls
    }

    /// The step's picture when the run's search returned it as a thumbnail; nil otherwise.
    func url(for step: InteractiveBlock.Steps.Step) -> URL? {
        guard let image = step.image, let url = SearchMediaPolicy.fetchableURL(image), urls.contains(url) else {
            return nil
        }
        return url
    }
}

/// A reply's illustrated steps (`exodus-steps`): a numbered card, each step its text and, when its picture is one of
/// the run's search thumbnails, that picture, loaded on sight as the gallery loads its thumbnails. A picture that is
/// anything else is dropped — never fetched, never a tap-to-load (spec 2026-10-07 §2.1).
struct StepsBlockView: View {
    let block: InteractiveBlock.Steps
    let pictures: StepsPictures

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title = block.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                Text(verbatim: title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(Array(block.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(verbatim: "\(index + 1)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .frame(width: 24, height: 24)
                        .background(.fill.tertiary, in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: step.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = pictures.url(for: step) {
                            StepPicture(url: url)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(verbatim: "\(index + 1). \(step.text)"))
            }
        }
        .padding(CardStyle.inset)
        .modifier(CardSurface())
    }
}

/// One step's thumbnail: a quiet block while it loads, the picture once in, nothing when it failed.
private struct StepPicture: View {
    let url: URL
    @State private var image: UIImage?
    @State private var failed = false
    @Environment(\.searchMediaLoader) private var loader

    var body: some View {
        if !failed {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.fill.quaternary)
                }
            }
            .frame(maxWidth: 280)
            .frame(height: 140)
            .clipShape(CardStyle.innerShape)
            .accessibilityHidden(true)
            .task(id: url) {
                if let cached = loader.cached(url, maxPixelSize: SearchMediaLoader.thumbnailPixelCap) {
                    image = cached
                    return
                }
                do {
                    image = try await loader.load(url, maxPixelSize: SearchMediaLoader.thumbnailPixelCap)
                } catch {
                    failed = true
                }
            }
        }
    }
}
